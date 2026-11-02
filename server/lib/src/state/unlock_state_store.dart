import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:threemojo_server/src/secure_file.dart';

/// Ciò che si conserva dei pagamenti oltre un riavvio — **solo questo**:
/// - [unlocks]: SHA-256 del token di sblocco → ora dello sblocco (UTC),
///   finché lo sblocco vale (2 ore);
/// - [transactions]: HMAC della transazione → data del riscatto e, se vale
///   ancora, SHA-256 del suo token, per 8 giorni.
///
/// Nessun dato personale: né il token né la transazione in chiaro, né
/// IP, né account, né dispositivo (l'app non ne ha: sessioni anonime).
class UnlockSnapshot {
  const UnlockSnapshot({this.unlocks = const {}, this.transactions = const {}});

  final Map<String, DateTime> unlocks;
  final Map<String, ({DateTime redeemedAt, String? tokenHash})> transactions;

  bool get isEmpty => unlocks.isEmpty && transactions.isEmpty;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'unlocks': [
      for (final entry in unlocks.entries)
        {'h': entry.key, 'at': entry.value.toUtc().toIso8601String()},
    ],
    'transactions': [
      for (final entry in transactions.entries)
        {
          'h': entry.key,
          'at': entry.value.redeemedAt.toUtc().toIso8601String(),
          if (entry.value.tokenHash != null) 't': entry.value.tokenHash,
        },
    ],
  };

  /// Lancia `FormatException` se il JSON non è un file nostro.
  factory UnlockSnapshot.fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) {
      throw const FormatException('stato degli sblocchi non riconosciuto');
    }
    final unlocks = <String, DateTime>{};
    for (final item in (json['unlocks'] as List? ?? const [])) {
      if (item is Map && item['h'] is String && item['at'] is String) {
        unlocks[item['h'] as String] = DateTime.parse(item['at'] as String);
      }
    }
    final transactions = <String, ({DateTime redeemedAt, String? tokenHash})>{};
    for (final item in (json['transactions'] as List? ?? const [])) {
      if (item is Map && item['h'] is String && item['at'] is String) {
        transactions[item['h'] as String] = (
          redeemedAt: DateTime.parse(item['at'] as String),
          tokenHash: item['t'] is String ? item['t'] as String : null,
        );
      }
    }
    return UnlockSnapshot(unlocks: unlocks, transactions: transactions);
  }
}

/// Il file di stato degli sblocchi: **un file** (`unlocks.state`) in
/// [directory], cifrato AES-256-GCM, scritto in modo atomico e `600`.
///
/// **Perché un file e non SQLite.** Sono poche decine di righe al giorno
/// (un riga per acquisto, scadenza a 2 ore / 8 giorni) e il server è un
/// unico processo: un file riscritto per intero ogni volta è più semplice
/// e robusto di un database — nessuna libreria nativa da compilare in
/// un'immagine Docker minimale (`sqlite3` per Dart richiede la libreria
/// di sistema o un build hook), nessun file `-wal`/`-shm`, nessun
/// problema di versione. L'atomicità la dà `rename` (si vede il file
/// vecchio o quello nuovo, mai uno a metà); la serializzazione delle
/// scritture, `UnlockStatePersistence`. Se un giorno servissero più
/// processi o migliaia di acquisti al giorno, qui si sostituisce con un
/// database senza toccare il resto (l'interfaccia è `load`/`save`).
///
/// **Cifratura**: la chiave è derivata da `PAYMENTS_TRANSACTION_HASH_KEY`
/// (HMAC-SHA256 con un'etichetta fissa: la chiave dell'HMAC delle
/// transazioni e quella del file non sono la stessa). Il file contiene solo
/// hash, quindi la cifratura è un secondo strato: chi lo copia senza la
/// chiave non può nemmeno confrontarlo con dei token.
///
/// Formato: `RUS1` + nonce (12) + testo cifrato + MAC (16); dato
/// autenticato aggiuntivo: il nome del file.
class UnlockStateStore {
  UnlockStateStore({required this.directory, required List<int> key})
    : _rootKey = List.unmodifiable(key);

  static const fileName = 'unlocks.state';
  static const _magic = [0x52, 0x55, 0x53, 0x31]; // "RUS1"
  static const _nonceLength = 12;
  static const _macLength = 16;
  static const _keyLabel = 'raen-unlock-state-file-v1';

  final Directory directory;
  final List<int> _rootKey;
  final AesGcm _algorithm = AesGcm.with256bits();
  SecretKey? _derived;

  File get file => File('${directory.path}${Platform.pathSeparator}$fileName');

  Future<SecretKey> _key() async {
    final cached = _derived;
    if (cached != null) return cached;
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(_keyLabel),
      secretKey: SecretKey(_rootKey),
    );
    return _derived = SecretKey(mac.bytes);
  }

  /// Lo stato salvato, o `null` se non c'è. Lancia `FormatException` se il
  /// file c'è ma non si decifra (chiave cambiata, file rovinato): chi chiama
  /// decide — il server lo scrive nel log e riparte da vuoto.
  Future<UnlockSnapshot?> load() async {
    final target = file;
    if (!await target.exists()) return null;
    final bytes = await target.readAsBytes();
    const header = 4 + _nonceLength;
    if (bytes.length < header + _macLength) {
      throw const FormatException('file di stato troppo corto');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException('file di stato non riconosciuto');
      }
    }
    final List<int> clear;
    try {
      clear = await _algorithm.decrypt(
        SecretBox(
          bytes.sublist(header, bytes.length - _macLength),
          nonce: bytes.sublist(4, header),
          mac: Mac(bytes.sublist(bytes.length - _macLength)),
        ),
        secretKey: await _key(),
        aad: utf8.encode(fileName),
      );
    } catch (_) {
      throw const FormatException('file di stato non decifrabile');
    }
    return UnlockSnapshot.fromJson(jsonDecode(utf8.decode(clear)));
  }

  /// Sostituisce il file con [snapshot] (atomico, `600`).
  Future<void> save(UnlockSnapshot snapshot) async {
    await ensureSecureDirectory(directory);
    final box = await _algorithm.encrypt(
      utf8.encode(jsonEncode(snapshot.toJson())),
      secretKey: await _key(),
      aad: utf8.encode(fileName),
    );
    final bytes = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    await writeFileAtomically600(file, bytes.takeBytes());
  }
}
