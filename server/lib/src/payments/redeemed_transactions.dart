import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../paywall_store.dart';
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
/// **Persistenza**: il registro vive in RAM ma, con una
/// `PAYMENTS_TRANSACTION_HASH_KEY` fissa, `UnlockStatePersistence` lo salva
/// cifrato su disco — **solo** HMAC della transazione, data del riscatto e
/// SHA-256 del token, per [retention] (8 giorni) — così un riavvio non
/// permette di riscattare di nuovo la stessa transazione Apple (più giovane
/// di `UnlockPurchaseService.maxPurchaseAge`). Senza chiave fissa (solo
/// sviluppo) l'HMAC cambia a ogni processo e il registro resta in RAM.
///
/// Dopo un riavvio il token **in chiaro** non c'è più (su disco c'è solo il
/// suo hash): un nuovo tentativo della stessa transazione riceve 409 anche
/// se lo sblocco vale ancora — lo sblocco resta valido per il client, che
/// ha già il token. Vedi `server/README.md`.
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

  /// Chiamata a ogni cambiamento da salvare: la imposta
  /// `UnlockStatePersistence`.
  void Function()? onChanged;

  /// `null` se mai riscattata (o uscita dal registro); altrimenti il token
  /// ancora associato (`unlockToken` è `null` se non c'è più in chiaro:
  /// dopo un riavvio, o dimenticato perché scaduto/revocato).
  ({String? unlockToken})? lookup(String transactionHash) {
    _prune();
    final entry = _entries[transactionHash];
    if (entry == null) return null;
    return (unlockToken: entry.unlockToken);
  }

  void record(String transactionHash, String unlockToken) {
    _prune();
    _entries[transactionHash] = _Entry(
      _now(),
      tokenHash: PaywallStore.hashToken(unlockToken),
      unlockToken: unlockToken,
    );
    onChanged?.call();
  }

  /// Annulla un riscatto non andato a buon fine (es. Google non ha
  /// consumato): il client potrà riprovare.
  void remove(String transactionHash) {
    if (_entries.remove(transactionHash) != null) onChanged?.call();
  }

  /// Dimentica il token (scaduto o revocato) ma ricorda che la transazione
  /// è stata riscattata. Ritorna l'**hash** del token che c'era (anche dopo
  /// un riavvio, quando il chiaro non c'è più), per revocarlo.
  String? forgetToken(String transactionHash) {
    final entry = _entries[transactionHash];
    if (entry == null) return null;
    final tokenHash = entry.tokenHash;
    entry
      ..unlockToken = null
      ..tokenHash = null;
    if (tokenHash != null) onChanged?.call();
    return tokenHash;
  }

  /// Segna la transazione come riscattata senza token (es. un rimborso
  /// notificato prima che l'app l'abbia riscattata): un riscatto
  /// successivo è rifiutato.
  void markRedeemed(String transactionHash) {
    _prune();
    if (_entries.containsKey(transactionHash)) return;
    _entries[transactionHash] = _Entry(_now());
    onChanged?.call();
  }

  int get length => _entries.length;

  /// Il registro per il salvataggio: hash della transazione → data del
  /// riscatto e hash del token (solo finché vale). Senza le voci scadute.
  Map<String, ({DateTime redeemedAt, String? tokenHash})> exportEntries() {
    _prune();
    return {
      for (final entry in _entries.entries)
        entry.key: (
          redeemedAt: entry.value.redeemedAt,
          tokenHash: entry.value.tokenHash,
        ),
    };
  }

  /// Rimette le voci salvate (all'avvio), scartando quelle uscite dalla
  /// [retention]. Non sostituisce quelle già presenti.
  void restoreEntries(
    Map<String, ({DateTime redeemedAt, String? tokenHash})> entries,
  ) {
    final now = _now();
    for (final entry in entries.entries) {
      if (now.difference(entry.value.redeemedAt) >= retention) continue;
      _entries.putIfAbsent(
        entry.key,
        () => _Entry(entry.value.redeemedAt, tokenHash: entry.value.tokenHash),
      );
    }
  }

  void _prune() {
    final now = _now();
    _entries.removeWhere(
      (_, entry) => now.difference(entry.redeemedAt) >= retention,
    );
  }
}

class _Entry {
  _Entry(this.redeemedAt, {this.tokenHash, this.unlockToken});

  final DateTime redeemedAt;

  /// SHA-256 del token: è ciò che si salva su disco.
  String? tokenHash;

  /// Il token in chiaro, **solo in RAM** e solo finché il processo vive.
  String? unlockToken;
}
