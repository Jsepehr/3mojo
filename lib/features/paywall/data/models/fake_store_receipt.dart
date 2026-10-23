import 'dart:convert';

import 'package:crypto/crypto.dart';

import '/core/config/store_config.dart';

/// La "ricevuta" del negozio **simulato** (`StoreBillingDataSourceFakeImpl`):
/// `fake-store-v1.<base64url(JSON)>.<base64url(HMAC-SHA256)>`, con JSON
/// `{"transactionId", "productId", "purchasedAt"}` e HMAC con la chiave
/// pubblica `StoreConfig.fakeStoreSigningKey`.
///
/// Stesso formato di `FakeReceiptVerifier` sul server (che la accetta solo
/// con `PAYMENTS_MODE=fake`). La firma non protegge nulla — la chiave è nel
/// codice — ma rende una ricevuta finta riconoscibile a colpo d'occhio e fa
/// percorrere al server lo stesso cammino di verifica di quelle vere.
class FakeStoreReceipt {
  const FakeStoreReceipt({
    required this.transactionId,
    required this.productId,
    required this.purchasedAt,
  });

  static const prefix = 'fake-store-v1';

  final String transactionId;
  final String productId;
  final DateTime purchasedAt;

  String encode() {
    final payload = _base64Url(
      utf8.encode(
        jsonEncode({
          'transactionId': transactionId,
          'productId': productId,
          'purchasedAt': purchasedAt.toUtc().toIso8601String(),
        }),
      ),
    );
    final signedPart = '$prefix.$payload';
    return '$signedPart.${sign(signedPart)}';
  }

  /// La ricevuta, se è una ricevuta finta integra; altrimenti `null`.
  static FakeStoreReceipt? decode(String receipt) {
    final parts = receipt.split('.');
    if (parts.length != 3 || parts[0] != prefix) return null;
    if (sign('${parts[0]}.${parts[1]}') != parts[2]) return null;
    try {
      final json = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (json is! Map<String, dynamic>) return null;
      final transactionId = json['transactionId'];
      final productId = json['productId'];
      final purchasedAt = DateTime.tryParse('${json['purchasedAt']}');
      if (transactionId is! String ||
          productId is! String ||
          purchasedAt == null) {
        return null;
      }
      return FakeStoreReceipt(
        transactionId: transactionId,
        productId: productId,
        purchasedAt: purchasedAt,
      );
    } on FormatException {
      return null;
    }
  }

  /// La firma (base64url senza `=`) di [signedPart].
  static String sign(String signedPart) => _base64Url(
    Hmac(
      sha256,
      utf8.encode(StoreConfig.fakeStoreSigningKey),
    ).convert(utf8.encode(signedPart)).bytes,
  );

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
