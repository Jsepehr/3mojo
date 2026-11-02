import 'dart:async';

import 'package:threemojo_server/src/log.dart';
import 'package:threemojo_server/src/payments/redeemed_transactions.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/state/unlock_state_store.dart';

/// Tiene allineati su disco `PaywallStore` (sblocchi attivi) e
/// `RedeemedTransactions` (transazioni riscattate): all'avvio li riempie
/// da [UnlockStateStore], poi riscrive il file a ogni cambiamento.
///
/// - **Scritture serializzate e raggruppate**: più cambiamenti ravvicinati
///   fanno una sola scrittura; non ce ne sono mai due insieme, e l'ultima
///   riscrive sempre lo stato più recente.
/// - **[flush]** completa quando lo stato attuale è su disco: il riscatto di
///   un acquisto lo aspetta prima di rispondere (`UnlockPurchaseService`).
///   Non lancia mai: se il disco fallisce si scrive nel log e il server
///   continua in RAM (meglio un acquisto valido ora che un errore a chi ha
///   pagato; il rischio residuo è documentato in `server/README.md`).
/// - **Pulizia**: ciò che è scaduto (sblocchi dopo 2 ore, transazioni dopo
///   8 giorni) non viene salvato; [compact] la applica anche a un server
///   fermo (la chiama un timer, vedi `Payments.start`).
class UnlockStatePersistence {
  UnlockStatePersistence({
    required UnlockStateStore store,
    required PaywallStore paywall,
    required RedeemedTransactions registry,
  }) : _store = store,
       _paywall = paywall,
       _registry = registry {
    _paywall.onChanged = markDirty;
    _registry.onChanged = markDirty;
  }

  final UnlockStateStore _store;
  final PaywallStore _paywall;
  final RedeemedTransactions _registry;

  Future<void>? _running;
  bool _dirty = false;
  bool _restored = false;
  int saveFailures = 0;

  /// Quante voci aveva il file all'ultima lettura/scrittura: [compact] lo
  /// riscrive solo se nel frattempo qualcosa è scaduto.
  int _onDiskUnlocks = 0;
  int _onDiskTransactions = 0;

  /// Rimette in RAM lo stato salvato. Un file illeggibile (chiave
  /// cambiata, rovinato) non ferma il server: lo scrive nel log, riparte da
  /// vuoto e lo sovrascrive. Ritorna quante voci ha ripreso.
  Future<({int unlocks, int transactions})> restore() async {
    UnlockSnapshot? snapshot;
    try {
      snapshot = await _store.load();
    } catch (error) {
      Log.error('state.restore_failed', error: error);
    }
    _restored = true;
    if (snapshot == null) return (unlocks: 0, transactions: 0);
    _onDiskUnlocks = snapshot.unlocks.length;
    _onDiskTransactions = snapshot.transactions.length;
    _paywall.restoreUnlocks(snapshot.unlocks);
    _registry.restoreEntries(snapshot.transactions);
    final restored = (
      unlocks: _paywall.activeCount,
      transactions: _registry.length,
    );
    // Se nel file c'era roba scaduta, la si toglie subito.
    if (restored.unlocks != snapshot.unlocks.length ||
        restored.transactions != snapshot.transactions.length) {
      markDirty();
    }
    return restored;
  }

  UnlockSnapshot snapshot() => UnlockSnapshot(
    unlocks: _paywall.exportUnlocks(),
    transactions: _registry.exportEntries(),
  );

  /// Segna che c'è qualcosa da salvare (la scrittura parte subito dopo, a
  /// fine del ciclo di eventi corrente).
  void markDirty() {
    _dirty = true;
    _running ??= Future.microtask(_drain);
  }

  /// Completa quando lo stato attuale è su disco.
  Future<void> flush() {
    _dirty = true;
    return _running ??= Future.microtask(_drain);
  }

  Future<void> _drain() async {
    try {
      while (_dirty) {
        _dirty = false;
        try {
          final current = snapshot();
          await _store.save(current);
          _onDiskUnlocks = current.unlocks.length;
          _onDiskTransactions = current.transactions.length;
        } catch (error, stackTrace) {
          saveFailures++;
          Log.error('state.save_failed', error: error, stackTrace: stackTrace);
        }
      }
    } finally {
      _running = null;
    }
  }

  /// Toglie ciò che è scaduto e, se c'era, riscrive il file.
  Future<void> compact() async {
    if (!_restored) return;
    final current = snapshot();
    if (current.unlocks.length != _onDiskUnlocks ||
        current.transactions.length != _onDiskTransactions) {
      await flush();
    }
  }
}
