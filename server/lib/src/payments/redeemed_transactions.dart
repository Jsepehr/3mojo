import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'receipt_verifier.dart';

/// Il registro delle transazioni **già riscattate**: impedisce che lo stesso
/// acquisto generi due sblocchi, e fa sì che un nuovo tentativo dopo una
/// risposta persa (rete caduta tra server e app) riceva **lo stesso**
/// token invece di un errore.
///
/// **Niente dati personali**: la chiave è un HMAC-SHA256 di
/// `piattaforma:transazione` (iOS `transactionId`, Android
/// `purchaseToken`), mai la transazione in chiaro. La chiave HMAC è
/// `PAYMENTS_TRANSACTION_HASH_KEY` o, senza, una casuale per processo:
/// così gli hash non si possono confrontare con i dati di Apple/Google
/// fuori dal server.
///
/// Per ogni hash si tiene il token di sblocco **solo finché il token
/// vale** (serve a ridarlo a un nuovo tentativo e a revocarlo con un
/// rimborso, `StoreNotifications`); dopo resta solo "già riscattato", fino
/// a [retention] dal riscatto.
///
/// **In RAM**, come il resto del server: un riavvio lo svuota. Per Google
/// non è un problema (l'acquisto è già consumato da Google stesso); per
/// Apple, dopo un riavvio, la stessa transazione potrebbe essere riscattata
/// di nuovo finché è più giovane di `UnlockPurchaseService.maxPurchaseAge`
/// — solo da chi ha già pagato una volta. Per chiudere anche questo:
/// stesso registro su disco/database (solo hash + data, cancellati dopo
/// [retention]) con `PAYMENTS_TRANSACTION_HASH_KEY` fissa. Vedi
/// `server/README.md`.
class RedeemedTransactions {
  RedeemedTransactions({
    List<int>? hashKey,
    DateTime Function()? now,
    this.retention = const Duration(days: 8),
  }) : _hashKey = SecretKey(hashKey ?? _randomKey()),
       _now = now ?? DateTime.now;

  final SecretKey _hashKey;
  final DateTime Function() _now;

  /// Quanto resta un hash nel registro: più del limite d'età degli
  /// acquisti riscattabili (`UnlockPurchaseService.maxPurchaseAge`, 7
  /// giorni), così nessuna transazione ancora riscattabile ne esce.
  final Duration retention;

  final Map<String, _Entry> _entries = {};

  static Uint8List _randomKey() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
  }

  /// L'hash con cui la transazione compare nel registro.
  Future<String> hash(StorePlatform platform, String transactionKey) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode('${platform.name}:$transactionKey'),
      secretKey: _hashKey,
    );
    return mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// `null` se mai riscattata (o uscita dal registro); altrimenti il token
  /// ancora associato (`null` dentro il record se non vale più).
  ({String? unlockToken})? lookup(String transactionHash) {
    _prune();
    final entry = _entries[transactionHash];
    if (entry == null) return null;
    return (unlockToken: entry.unlockToken);
  }

  void record(String transactionHash, String unlockToken) {
    _prune();
    _entries[transactionHash] = _Entry(_now(), unlockToken);
  }

  /// Annulla un riscatto non andato a buon fine (es. Google non ha
  /// consumato): il client potrà riprovare.
  void remove(String transactionHash) => _entries.remove(transactionHash);

  /// Dimentica il token (scaduto o revocato) ma ricorda che la transazione
  /// è stata riscattata. Ritorna il token che c'era.
  String? forgetToken(String transactionHash) {
    final entry = _entries[transactionHash];
    final token = entry?.unlockToken;
    entry?.unlockToken = null;
    return token;
  }

  /// Segna la transazione come riscattata senza token (es. un rimborso
  /// notificato prima che l'app l'abbia riscattata): un riscatto
  /// successivo è rifiutato.
  void markRedeemed(String transactionHash) {
    _prune();
    _entries.putIfAbsent(transactionHash, () => _Entry(_now(), null));
  }

  int get length => _entries.length;

  void _prune() {
    final now = _now();
    _entries.removeWhere(
      (_, entry) => now.difference(entry.redeemedAt) >= retention,
    );
  }
}

class _Entry {
  _Entry(this.redeemedAt, this.unlockToken);

  final DateTime redeemedAt;
  String? unlockToken;
}
