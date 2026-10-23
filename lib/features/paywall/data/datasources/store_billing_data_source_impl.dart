import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '/core/errors/exceptions.dart';
import '../../domain/entities/store_checkout.dart';
import '../../domain/entities/store_purchase.dart';
import '../../domain/entities/unlock_offer.dart';
import 'store_billing_data_source.dart';

/// Implementazione **reale**: App Store (StoreKit 2) e Google Play Billing
/// tramite il pacchetto ufficiale `in_app_purchase`.
///
/// - Con [productId] `null` (build senza configurazione, web/desktop) non
///   tocca mai il plugin: ogni chiamata lancia `StoreUnavailableException`
///   e il bottone dice "Non disponibile".
/// - Ascolta `purchaseStream` **dalla costruzione** (il provider è creato
///   all'avvio, `lazy: false`), come chiede il plugin: il negozio
///   ripresenta lì gli acquisti non completati dell'esecuzione precedente.
///   Su Android chiede anche `restorePurchases()`, che ripresenta gli
///   acquisti pagati ma non ancora consumati.
/// - `buyConsumable(autoConsume: false)`: su Android il plugin
///   consumerebbe l'acquisto **prima** che il server l'abbia verificato.
///   Lo si completa solo in [completePurchase], dopo la conferma del
///   server: Android `consumePurchase` (il server l'ha già consumato con la
///   Play Developer API: un errore qui è atteso e ignorato, serve solo ad
///   aggiornare la cache locale di Play), iOS `completePurchase`
///   (`finishTransaction`).
/// - Errori e annullamenti con `pendingCompletePurchase` vengono completati
///   subito (iOS li lascerebbe nella coda delle transazioni).
class StoreBillingDataSourceImpl implements StoreBillingDataSource {
  StoreBillingDataSourceImpl({
    required String? productId,
    InAppPurchase? inAppPurchase,
    StorePlatform? platform,
  }) : _productId = productId,
       _platform =
           platform ??
           (defaultTargetPlatform == TargetPlatform.android
               ? StorePlatform.googlePlay
               : StorePlatform.appStore) {
    if (productId == null) return;
    final iap = _iap = inAppPurchase ?? InAppPurchase.instance;
    _subscription = iap.purchaseStream.listen(
      _onPurchases,
      // Uno stream del plugin in errore non deve lasciare una finestra
      // d'acquisto appesa per sempre.
      onError: (Object error) {
        _failCheckout(StorePurchaseException('$error'));
      },
    );
    if (_platform == StorePlatform.googlePlay) {
      unawaited(iap.restorePurchases().catchError((Object _) {}));
    }
  }

  final String? _productId;
  final StorePlatform _platform;
  InAppPurchase? _iap;
  // ignore: unused_field
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  ProductDetails? _product;
  Completer<StoreCheckout>? _checkout;
  final Map<StorePurchase, PurchaseDetails> _details = {};
  final List<StorePurchase> _unfinished = [];
  final StreamController<StorePurchase> _outOfBand = StreamController();

  @override
  Future<UnlockOffer> loadUnlockOffer() async =>
      UnlockOffer.store((await _loadProduct()).price);

  Future<ProductDetails> _loadProduct() async {
    final cached = _product;
    if (cached != null) return cached;
    final iap = _iap;
    final productId = _productId;
    if (iap == null || productId == null) {
      throw const StoreUnavailableException('Store not configured');
    }
    try {
      if (!await iap.isAvailable()) {
        throw const StoreUnavailableException('Store not available');
      }
      final response = await iap.queryProductDetails({productId});
      final product = response.productDetails
          .where((p) => p.id == productId)
          .firstOrNull;
      if (response.error != null || product == null) {
        throw StoreUnavailableException(
          'Product $productId not found: ${response.error?.message}',
        );
      }
      return _product = product;
    } on StoreUnavailableException {
      rethrow;
    } catch (e) {
      throw StoreUnavailableException('$e');
    }
  }

  @override
  Future<StoreCheckout> buyUnlock() async {
    final product = await _loadProduct();
    if (_checkout != null) {
      throw const StorePurchaseException('A purchase is already in progress');
    }
    final checkout = _checkout = Completer<StoreCheckout>();
    try {
      final started = await _iap!.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
        autoConsume: false,
      );
      if (!started) {
        _failCheckout(const StorePurchaseException('Purchase not started'));
      }
    } catch (e) {
      _failCheckout(StorePurchaseException('$e'));
    }
    return checkout.future;
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final details in purchases) {
      if (details.productID != _productId) continue;
      switch (details.status) {
        case PurchaseStatus.pending:
          _finishCheckout(const StoreCheckoutPending());
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          final purchase = StorePurchase(
            platform: _platform,
            productId: details.productID,
            transactionId: details.purchaseID ?? '',
            verificationData: details.verificationData.serverVerificationData,
          );
          _details[purchase] = details;
          if (!_unfinished.contains(purchase)) _unfinished.add(purchase);
          final checkout = _checkout;
          if (checkout != null && details.status == PurchaseStatus.purchased) {
            _finishCheckout(StoreCheckoutPurchased(purchase));
          } else {
            _outOfBand.add(purchase);
          }
        case PurchaseStatus.error:
          _discard(details);
          _failCheckout(
            StorePurchaseException(details.error?.message ?? 'Store error'),
          );
        case PurchaseStatus.canceled:
          _discard(details);
          _failCheckout(const PurchaseCanceledException());
      }
    }
  }

  void _finishCheckout(StoreCheckout result) {
    final checkout = _checkout;
    _checkout = null;
    if (checkout != null && !checkout.isCompleted) checkout.complete(result);
  }

  void _failCheckout(Exception error) {
    final checkout = _checkout;
    _checkout = null;
    if (checkout != null && !checkout.isCompleted) {
      checkout.completeError(error);
    }
  }

  /// Un acquisto fallito o annullato non va consegnato, ma va tolto dalla
  /// coda del negozio.
  void _discard(PurchaseDetails details) {
    if (!details.pendingCompletePurchase) return;
    unawaited(_iap!.completePurchase(details).catchError((Object _) {}));
  }

  @override
  Stream<StorePurchase> get unfinishedPurchases => _outOfBand.stream;

  @override
  List<StorePurchase> get knownUnfinishedPurchases =>
      List.unmodifiable(_unfinished);

  @override
  Future<void> completePurchase(StorePurchase purchase) async {
    final details = _details[purchase];
    final iap = _iap;
    if (details != null && iap != null) {
      try {
        if (_platform == StorePlatform.googlePlay) {
          await iap
              .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
              .consumePurchase(details);
        } else if (details.pendingCompletePurchase) {
          await iap.completePurchase(details);
        }
      } catch (e) {
        throw StorePurchaseException('$e');
      }
    }
    _details.remove(purchase);
    _unfinished.remove(purchase);
  }
}
