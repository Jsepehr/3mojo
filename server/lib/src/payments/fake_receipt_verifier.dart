import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../constant_time.dart';
import 'receipt_verifier.dart';

/// Verifica le ricevute del **negozio simulato** dell'app
/// (`StoreBillingDataSourceFakeImpl`, solo build di debug). Usato **solo**
/// con `PAYMENTS_MODE=fake` (`PaymentsConfig`): in modalità reale la
/// piattaforma `fake` risponde 503.
///
/// Formato (identico a `FakeStoreReceipt` nell'app):
/// `fake-store-v1.<base64url(JSON)>.<base64url(HMAC-SHA256)>`, con JSON
/// `{"transactionId", "productId", "purchasedAt"}` e HMAC con la chiave
/// **pubblica** [signingKey]. La firma non protegge nulla (la chiave è nel
/// codice dell'app): serve solo a riconoscere a colpo d'occhio una ricevuta
/// finta e a scartare quelle rovinate, esercitando lo stesso percorso di
/// verifica di quelle vere.
class FakeReceiptVerifier implements ReceiptVerifier {
  const FakeReceiptVerifier();

  static const prefix = 'fake-store-v1';

  /// Lo stesso di `StoreConfig.fakeUnlockProductId` nell'app.
  static const productId = 'raen.fake.unlock_2h';

  /// Lo stesso di `StoreConfig.fakeStoreSigningKey` nell'app: **non** è un
  /// segreto.
  static const signingKey = 'raen-fake-store-not-a-real-payment';

  @override
  StorePlatform get platform => StorePlatform.fake;

  @override
  Future<VerifiedPurchase> verify(PurchaseClaim claim) async {
    final parts = claim.receipt.split('.');
    if (parts.length != 3 || parts[0] != prefix) {
      throw const ReceiptRejectedException(
        ReceiptRejection.invalidReceipt,
        'non è una ricevuta del negozio finto',
      );
    }
    final expected = await sign('${parts[0]}.${parts[1]}');
    if (!constantTimeEquals(expected, parts[2])) {
      throw const ReceiptRejectedException(
        ReceiptRejection.invalidReceipt,
        'firma della ricevuta finta non valida',
      );
    }

    final Object? payload;
    try {
      payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
    } on FormatException {
      throw const ReceiptRejectedException(ReceiptRejection.invalidReceipt);
    }
    if (payload is! Map<String, dynamic>) {
      throw const ReceiptRejectedException(ReceiptRejection.invalidReceipt);
    }
    final transactionId = payload['transactionId'];
    final product = payload['productId'];
    final purchasedAt = DateTime.tryParse('${payload['purchasedAt']}');
    if (transactionId is! String ||
        transactionId.isEmpty ||
        product is! String ||
        purchasedAt == null) {
      throw const ReceiptRejectedException(ReceiptRejection.invalidReceipt);
    }
    if (transactionId != claim.transactionId) {
      throw const ReceiptRejectedException(
        ReceiptRejection.transactionMismatch,
      );
    }
    return VerifiedPurchase(
      platform: StorePlatform.fake,
      transactionKey: transactionId,
      productId: product,
      purchasedAt: purchasedAt,
    );
  }

  @override
  Future<void> finalize(VerifiedPurchase purchase) async {}

  /// La firma (base64url senza `=`) di [signedPart]; usata anche dai test
  /// per fabbricare ricevute finte.
  static Future<String> sign(String signedPart) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(signedPart),
      secretKey: SecretKey(utf8.encode(signingKey)),
    );
    return base64Url.encode(mac.bytes).replaceAll('=', '');
  }

  /// Una ricevuta finta completa — per i test e per gli strumenti.
  static Future<String> buildReceipt({
    required String transactionId,
    String product = productId,
    required DateTime purchasedAt,
  }) async {
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'transactionId': transactionId,
              'productId': product,
              'purchasedAt': purchasedAt.toUtc().toIso8601String(),
            }),
          ),
        )
        .replaceAll('=', '');
    final signedPart = '$prefix.$payload';
    return '$signedPart.${await sign(signedPart)}';
  }
}
