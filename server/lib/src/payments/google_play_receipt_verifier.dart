import 'google_play_api.dart';
import 'receipt_verifier.dart';

/// Verifica un acquisto Google Play chiedendo a Google la `ProductPurchase`
/// del `purchaseToken` (`purchases.products.get`) e, dopo l'emissione del
/// token di sblocco, la **consuma** dal server ([finalize],
/// `purchases.products.consume`): da lì Google stesso non la considera più
/// riscattabile, anche se il registro in RAM si perdesse con un riavvio.
///
/// Campi della risposta usati (documentazione `ProductPurchase`):
/// - `purchaseState`: 0 acquistato, 1 annullato, 2 in attesa → solo 0;
/// - `consumptionState`: 0 da consumare, 1 consumato → 1 = già riscattato
///   (lo decide `UnlockPurchaseService` col registro: un nuovo tentativo
///   dopo una risposta persa riceve lo stesso token);
/// - `productId` (se presente) e `orderId` confrontati con quanto dichiara
///   il client;
/// - `purchaseTimeMillis`: l'ora dell'acquisto.
///
/// Gli acquisti di prova (`purchaseType` 0, account "tester di licenze")
/// sono accettati: Google li usa anche per la revisione.
class GooglePlayReceiptVerifier implements ReceiptVerifier {
  GooglePlayReceiptVerifier({required GooglePlayApi api}) : _api = api;

  final GooglePlayApi _api;

  @override
  StorePlatform get platform => StorePlatform.android;

  @override
  Future<VerifiedPurchase> verify(PurchaseClaim claim) async {
    final token = claim.receipt;
    if (token.isEmpty || token.length > 4096) {
      throw const ReceiptRejectedException(ReceiptRejection.invalidReceipt);
    }
    final purchase = await _api.getProductPurchase(
      productId: claim.productId,
      purchaseToken: token,
    );
    return verifiedFromResponse(purchase, claim);
  }

  /// I controlli sulla risposta di Google (pubblico per i test).
  static VerifiedPurchase verifiedFromResponse(
    Map<String, dynamic> purchase,
    PurchaseClaim claim,
  ) {
    final kind = purchase['kind'];
    if (kind != null && kind != 'androidpublisher#productPurchase') {
      throw const ReceiptRejectedException(ReceiptRejection.invalidReceipt);
    }
    switch (purchase['purchaseState']) {
      case 0:
        break;
      case 1:
        throw const ReceiptRejectedException(
          ReceiptRejection.notPurchased,
          'annullato',
        );
      case 2:
        throw const ReceiptRejectedException(
          ReceiptRejection.notPurchased,
          'in attesa di pagamento',
        );
      default:
        throw const ReceiptRejectedException(ReceiptRejection.invalidReceipt);
    }
    final productId = purchase['productId'] ?? claim.productId;
    if (productId is! String) {
      throw const ReceiptRejectedException(ReceiptRejection.invalidReceipt);
    }
    final orderId = purchase['orderId'];
    if (orderId is String &&
        orderId.isNotEmpty &&
        claim.transactionId.isNotEmpty &&
        orderId != claim.transactionId) {
      throw const ReceiptRejectedException(
        ReceiptRejection.transactionMismatch,
      );
    }
    final millis = int.tryParse('${purchase['purchaseTimeMillis']}');
    if (millis == null) {
      throw const ReceiptRejectedException(ReceiptRejection.invalidReceipt);
    }
    return VerifiedPurchase(
      platform: StorePlatform.android,
      transactionKey: claim.receipt,
      productId: productId,
      purchasedAt: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
      alreadyConsumed: purchase['consumptionState'] == 1,
      storeEnforcesSingleUse: true,
    );
  }

  @override
  Future<void> finalize(VerifiedPurchase purchase) => _api.consume(
    productId: purchase.productId,
    purchaseToken: purchase.transactionKey,
  );
}
