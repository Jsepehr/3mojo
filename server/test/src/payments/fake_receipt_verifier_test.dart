import 'package:test/test.dart';
import 'package:threemojo_server/src/payments/fake_receipt_verifier.dart';
import 'package:threemojo_server/src/payments/receipt_verifier.dart';

Matcher _rejected(ReceiptRejection reason) => throwsA(
  isA<ReceiptRejectedException>().having((e) => e.reason, 'reason', reason),
);

PurchaseClaim _claim(String receipt, {String transactionId = 'fake-tx-1'}) =>
    PurchaseClaim(
      platform: StorePlatform.fake,
      productId: FakeReceiptVerifier.productId,
      receipt: receipt,
      transactionId: transactionId,
    );

void main() {
  const verifier = FakeReceiptVerifier();
  final purchasedAt = DateTime.utc(2026, 10, 23, 9, 15);

  test('accepts a receipt of the simulated store', () async {
    final receipt = await FakeReceiptVerifier.buildReceipt(
      transactionId: 'fake-tx-1',
      purchasedAt: purchasedAt,
    );

    final verified = await verifier.verify(_claim(receipt));

    expect(receipt, startsWith('fake-store-v1.'));
    expect(verified.transactionKey, 'fake-tx-1');
    expect(verified.productId, FakeReceiptVerifier.productId);
    expect(verified.purchasedAt, purchasedAt);
  });

  test('the same format as the app (golden: same key, same HMAC)', () async {
    // Valore calcolato a parte (HMAC-SHA256 standard) e identico a quello
    // di `FakeStoreReceipt` nell'app: se uno dei due
    // lati cambia formato o chiave, questo test (e quello gemello nell'app)
    // si rompe.
    expect(
      await FakeReceiptVerifier.sign('fake-store-v1.eyJhIjoxfQ'),
      'LLfo3GhM_V-1Nun58mbJcrTN2QrUdJqfWDWlYokf-VI',
    );
  });

  test('a tampered payload or signature is rejected', () async {
    final receipt = await FakeReceiptVerifier.buildReceipt(
      transactionId: 'fake-tx-1',
      purchasedAt: purchasedAt,
    );
    final parts = receipt.split('.');

    await expectLater(
      verifier.verify(_claim('${parts[0]}.${parts[1]}x.${parts[2]}')),
      _rejected(ReceiptRejection.invalidReceipt),
    );
    await expectLater(
      verifier.verify(_claim('${parts[0]}.${parts[1]}.AAAA')),
      _rejected(ReceiptRejection.invalidReceipt),
    );
  });

  test('real receipts (a JWS, a Play token) are not fake receipts', () async {
    for (final receipt in ['eyJhbGciOiJFUzI1NiJ9.e30.sig', 'purchase-token']) {
      await expectLater(
        verifier.verify(_claim(receipt)),
        _rejected(ReceiptRejection.invalidReceipt),
      );
    }
  });

  test('the declared transaction must be the one in the receipt', () async {
    final receipt = await FakeReceiptVerifier.buildReceipt(
      transactionId: 'fake-tx-1',
      purchasedAt: purchasedAt,
    );

    await expectLater(
      verifier.verify(_claim(receipt, transactionId: 'fake-tx-2')),
      _rejected(ReceiptRejection.transactionMismatch),
    );
  });
}
