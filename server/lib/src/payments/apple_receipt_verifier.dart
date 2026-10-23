import 'app_store_server_api.dart';
import 'apple_jws_verifier.dart';
import 'payments_config.dart';
import 'receipt_verifier.dart';

/// Verifica un acquisto App Store.
///
/// 1. Se l'app ha mandato la transazione firmata di StoreKit 2 (JWS, il
///    caso normale con `in_app_purchase` ≥ 3.2), la si verifica **qui**
///    (`AppleJwsVerifier`: catena fino ad Apple Root CA - G3, firma ES256):
///    non serve chiamare Apple.
/// 2. Altrimenti (StoreKit 1, ricevuta dell'app in base64) la si chiede ad
///    Apple con `transactionId` ([AppStoreServerApi], servono le
///    credenziali `APPLE_ISSUER_ID`/`APPLE_KEY_ID`/`APPLE_PRIVATE_KEY_PATH`).
///
/// Poi controlla il contenuto: stessa app (`bundleId`), ambiente ammesso,
/// tipo `Consumable`, non rimborsata (`revocationDate`), e che il
/// `transactionId` dichiarato sia quello firmato. Il prodotto lo controlla
/// `UnlockPurchaseService`, con quello **firmato** (non quello dichiarato).
class AppleReceiptVerifier implements ReceiptVerifier {
  AppleReceiptVerifier({
    required AppleStoreSettings settings,
    AppleJwsVerifier? jwsVerifier,
    AppStoreServerApi? api,
  }) : _settings = settings,
       _jwsVerifier =
           jwsVerifier ?? AppleJwsVerifier(trustedRoots: settings.trustedRoots),
       _api = api;

  final AppleStoreSettings _settings;
  final AppleJwsVerifier _jwsVerifier;
  final AppStoreServerApi? _api;

  @override
  StorePlatform get platform => StorePlatform.ios;

  @override
  Future<VerifiedPurchase> verify(PurchaseClaim claim) async {
    final String jws;
    if (AppleJwsVerifier.looksLikeJws(claim.receipt)) {
      jws = claim.receipt;
    } else {
      final api = _api;
      if (api == null) {
        throw const StoreNotConfiguredException(
          'ricevuta senza transazione firmata e API App Store non '
          'configurate (APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY_PATH)',
        );
      }
      jws = await api.getSignedTransaction(claim.transactionId);
    }
    return verifiedFromPayload(_jwsVerifier.verify(jws), claim);
  }

  /// I controlli sul contenuto di una transazione già verificata (anche
  /// quella dentro una notifica).
  VerifiedPurchase verifiedFromPayload(
    Map<String, dynamic> payload,
    PurchaseClaim claim,
  ) {
    if (payload['bundleId'] != _settings.bundleId) {
      throw const ReceiptRejectedException(ReceiptRejection.wrongApp);
    }
    if (!_settings.acceptedEnvironments.contains(payload['environment'])) {
      throw ReceiptRejectedException(
        ReceiptRejection.wrongEnvironment,
        '${payload['environment']}',
      );
    }
    final transactionId = payload['transactionId'];
    final productId = payload['productId'];
    final purchaseDate = payload['purchaseDate'];
    if (transactionId is! String ||
        transactionId.isEmpty ||
        productId is! String ||
        purchaseDate is! int) {
      throw const ReceiptRejectedException(
        ReceiptRejection.invalidReceipt,
        'transazione senza transactionId/productId/purchaseDate',
      );
    }
    if (payload['type'] != 'Consumable') {
      throw ReceiptRejectedException(
        ReceiptRejection.wrongProduct,
        'tipo ${payload['type']}',
      );
    }
    if (payload['revocationDate'] != null) {
      throw const ReceiptRejectedException(ReceiptRejection.refunded);
    }
    if (claim.transactionId.isNotEmpty &&
        claim.transactionId != transactionId) {
      throw const ReceiptRejectedException(
        ReceiptRejection.transactionMismatch,
      );
    }
    return VerifiedPurchase(
      platform: StorePlatform.ios,
      transactionKey: transactionId,
      productId: productId,
      purchasedAt: DateTime.fromMillisecondsSinceEpoch(
        purchaseDate,
        isUtc: true,
      ),
    );
  }

  /// Apple non ha un "consuma" lato server: il consumabile lo chiude l'app
  /// (`finishTransaction`, cioè `completePurchase`) dopo la nostra
  /// risposta. Il riuso della stessa transazione lo impediscono il
  /// registro e il limite d'età (`UnlockPurchaseService`).
  @override
  Future<void> finalize(VerifiedPurchase purchase) async {}
}
