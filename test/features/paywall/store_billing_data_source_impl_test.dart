import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'package:threemojo_app/core/errors/exceptions.dart';
import 'package:threemojo_app/features/paywall/data/datasources/store_billing_data_source_impl.dart';
import 'package:threemojo_app/features/paywall/domain/entities/store_checkout.dart';
import 'package:threemojo_app/features/paywall/domain/entities/store_purchase.dart';
import 'package:threemojo_app/features/paywall/domain/entities/unlock_offer.dart';

/// La piattaforma di `in_app_purchase` (StoreKit / Play Billing) finta: si
/// controlla cosa arriva sul `purchaseStream` e si registra cosa chiede
/// l'app.
class _FakeIapPlatform extends InAppPurchasePlatform {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  bool available = true;
  bool? lastAutoConsume;
  int buyCalls = 0;
  final completed = <PurchaseDetails>[];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async => ProductDetailsResponse(
    productDetails: [
      if (identifiers.contains('raen.unlock_2h'))
        ProductDetails(
          id: 'raen.unlock_2h',
          title: 'Unlock',
          description: '2 hours',
          price: '1,09 €',
          rawPrice: 1.09,
          currencyCode: 'EUR',
        ),
    ],
    notFoundIDs: [],
  );

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    buyCalls++;
    lastAutoConsume = autoConsume;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async =>
      completed.add(purchase);

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}
}

PurchaseDetails _details(
  PurchaseStatus status, {
  String id = '2000000123456789',
  String productId = 'raen.unlock_2h',
}) => PurchaseDetails(
  purchaseID: id,
  productID: productId,
  verificationData: PurchaseVerificationData(
    localVerificationData: '{}',
    serverVerificationData: 'eyJ.jws.$id',
    source: 'app_store',
  ),
  transactionDate: '1793000000000',
  status: status,
)..pendingCompletePurchase = status != PurchaseStatus.pending;

void main() {
  late _FakeIapPlatform platform;
  late StoreBillingDataSourceImpl store;

  setUp(() {
    // Nessuna piattaforma vera (StoreKit/Play) registrata nei test: il
    // facciata `InAppPurchase` delega a quella finta.
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    final iap = InAppPurchase.instance;
    debugDefaultTargetPlatformOverride = null;
    platform = _FakeIapPlatform();
    InAppPurchasePlatform.instance = platform;
    store = StoreBillingDataSourceImpl(
      productId: 'raen.unlock_2h',
      inAppPurchase: iap,
      platform: StorePlatform.appStore,
    );
  });

  test('the price is the one formatted by the store', () async {
    expect(await store.loadUnlockOffer(), const UnlockOffer.store('1,09 €'));
  });

  test('buys a consumable WITHOUT auto-consume, and completes it only when '
      'asked (after the server)', () async {
    final checkout = store.buyUnlock();
    await pumpEventQueue();
    platform.updates.add([_details(PurchaseStatus.purchased)]);

    final result = await checkout;

    expect(platform.lastAutoConsume, isFalse);
    expect(result, isA<StoreCheckoutPurchased>());
    final purchase = (result as StoreCheckoutPurchased).purchase;
    expect(purchase.verificationData, 'eyJ.jws.2000000123456789');
    expect(purchase.transactionId, '2000000123456789');
    expect(platform.completed, isEmpty);
    expect(store.knownUnfinishedPurchases, [purchase]);

    await store.completePurchase(purchase);

    expect(platform.completed, hasLength(1));
    expect(store.knownUnfinishedPurchases, isEmpty);
  });

  test('canceled → PurchaseCanceledException; error → '
      'StorePurchaseException; both taken off the store queue', () async {
    final canceled = store.buyUnlock();
    await pumpEventQueue();
    platform.updates.add([_details(PurchaseStatus.canceled)]);
    await expectLater(canceled, throwsA(isA<PurchaseCanceledException>()));

    final failed = store.buyUnlock();
    await pumpEventQueue();
    platform.updates.add([_details(PurchaseStatus.error, id: '2')]);
    await expectLater(failed, throwsA(isA<StorePurchaseException>()));

    await pumpEventQueue();
    expect(platform.completed, hasLength(2));
    expect(store.knownUnfinishedPurchases, isEmpty);
  });

  test('pending ends the checkout as pending; the later confirmation '
      'arrives among the unfinished purchases', () async {
    final unfinished = <StorePurchase>[];
    store.unfinishedPurchases.listen(unfinished.add);
    final checkout = store.buyUnlock();
    await pumpEventQueue();
    platform.updates.add([_details(PurchaseStatus.pending)]);

    expect(await checkout, isA<StoreCheckoutPending>());

    platform.updates.add([_details(PurchaseStatus.purchased)]);
    await pumpEventQueue();
    expect(unfinished, hasLength(1));
    expect(platform.completed, isEmpty);
  });

  test('a purchase left open by the previous run arrives at startup (and '
      'one of another product is ignored)', () async {
    final unfinished = <StorePurchase>[];
    platform.updates.add([
      _details(PurchaseStatus.purchased, id: '7'),
      _details(PurchaseStatus.purchased, id: '8', productId: 'other'),
    ]);
    await pumpEventQueue();
    store.unfinishedPurchases.listen(unfinished.add);
    await pumpEventQueue();

    expect(unfinished.map((p) => p.transactionId), ['7']);
    expect(platform.buyCalls, 0);
  });

  test('without a product id (release without configuration) the plugin '
      'is never touched', () async {
    final unavailable = StoreBillingDataSourceImpl(productId: null);

    await expectLater(
      unavailable.loadUnlockOffer(),
      throwsA(isA<StoreUnavailableException>()),
    );
    await expectLater(
      unavailable.buyUnlock(),
      throwsA(isA<StoreUnavailableException>()),
    );
    expect(platform.buyCalls, 0);
  });

  test('store not available → unavailable', () async {
    platform.available = false;

    await expectLater(
      store.loadUnlockOffer(),
      throwsA(isA<StoreUnavailableException>()),
    );
  });
}
