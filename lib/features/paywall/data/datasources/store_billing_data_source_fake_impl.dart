import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '/core/config/store_config.dart';
import '/core/errors/exceptions.dart';
import '../../domain/entities/store_checkout.dart';
import '../../domain/entities/store_purchase.dart';
import '../../domain/entities/unlock_offer.dart';
import '../models/fake_store_receipt.dart';
import 'store_billing_data_source.dart';

/// Come finisce la finestra del negozio simulato.
enum FakeStoreOutcome {
  success,
  canceled,
  error,

  /// "In attesa" (come i contanti su Google Play o "Chiedi di acquistare"):
  /// dopo `approvalDelay` l'acquisto arriva confermato tra quelli da
  /// riscattare.
  pending;

  /// Da `--dart-define=FAKE_STORE_OUTCOME=success|canceled|error|pending`
  /// (default `success`), per provare a mano ogni esito in debug.
  static FakeStoreOutcome fromEnvironment() {
    const raw = String.fromEnvironment('FAKE_STORE_OUTCOME');
    return values.firstWhere(
      (outcome) => outcome.name == raw,
      orElse: () => success,
    );
  }
}

/// Negozio **simulato** (nessun addebito, nessun account): imita il flusso
/// di `in_app_purchase` — un'attesa come la finestra nativa, poi l'esito
/// scelto ([outcome]); un acquisto pagato porta una ricevuta finta firmata
/// in modo riconoscibile (`FakeStoreReceipt`, `fake-store-v1.…`) che il
/// server accetta solo con `PAYMENTS_MODE=fake`; resta "da completare"
/// finché il server non ha confermato, come nel negozio vero.
///
/// **Solo nei build di debug**: in release il costruttore lancia (è
/// `StoreConfig.mode` a non sceglierlo mai, questa è la cintura in più).
class StoreBillingDataSourceFakeImpl implements StoreBillingDataSource {
  StoreBillingDataSourceFakeImpl({
    FakeStoreOutcome? outcome,
    this.sheetDelay = const Duration(milliseconds: 1200),
    this.approvalDelay = const Duration(seconds: 8),
    DateTime Function()? now,
    Iterable<StorePurchase> unfinishedAtStartup = const [],
  }) : outcome = outcome ?? FakeStoreOutcome.fromEnvironment(),
       _now = now ?? DateTime.now {
    if (kReleaseMode) {
      throw StateError('Il negozio simulato non esiste nei build di release');
    }
    for (final purchase in unfinishedAtStartup) {
      _unfinished.add(purchase);
      _outOfBand.add(purchase);
    }
  }

  /// Modificabile (test, prove a mano): vale per il prossimo acquisto.
  FakeStoreOutcome outcome;
  final Duration sheetDelay;
  final Duration approvalDelay;
  final DateTime Function() _now;

  final List<StorePurchase> _unfinished = [];
  final StreamController<StorePurchase> _outOfBand = StreamController();
  bool _sheetOpen = false;

  /// Gli acquisti completati (solo per i test).
  @visibleForTesting
  final List<StorePurchase> completed = [];

  /// Un acquisto pagato con una ricevuta finta valida (per i test e per
  /// [unfinishedAtStartup]).
  static StorePurchase newPurchase({DateTime? purchasedAt}) {
    final transactionId = 'fake-${const Uuid().v4()}';
    return StorePurchase(
      platform: StorePlatform.fake,
      productId: StoreConfig.fakeUnlockProductId,
      transactionId: transactionId,
      verificationData: FakeStoreReceipt(
        transactionId: transactionId,
        productId: StoreConfig.fakeUnlockProductId,
        purchasedAt: purchasedAt ?? DateTime.now(),
      ).encode(),
    );
  }

  @override
  Future<UnlockOffer> loadUnlockOffer() async => const UnlockOffer.simulated();

  @override
  Future<StoreCheckout> buyUnlock() async {
    if (_sheetOpen) {
      throw const StorePurchaseException('A purchase is already in progress');
    }
    _sheetOpen = true;
    try {
      await Future<void>.delayed(sheetDelay);
    } finally {
      _sheetOpen = false;
    }
    switch (outcome) {
      case FakeStoreOutcome.canceled:
        throw const PurchaseCanceledException();
      case FakeStoreOutcome.error:
        throw const StorePurchaseException('Simulated store error');
      case FakeStoreOutcome.pending:
        Timer(approvalDelay, () {
          final purchase = newPurchase(purchasedAt: _now());
          _unfinished.add(purchase);
          _outOfBand.add(purchase);
        });
        return const StoreCheckoutPending();
      case FakeStoreOutcome.success:
        final purchase = newPurchase(purchasedAt: _now());
        _unfinished.add(purchase);
        return StoreCheckoutPurchased(purchase);
    }
  }

  @override
  Stream<StorePurchase> get unfinishedPurchases => _outOfBand.stream;

  @override
  List<StorePurchase> get knownUnfinishedPurchases =>
      List.unmodifiable(_unfinished);

  @override
  Future<void> completePurchase(StorePurchase purchase) async {
    _unfinished.remove(purchase);
    completed.add(purchase);
  }
}
