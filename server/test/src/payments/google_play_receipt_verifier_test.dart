import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:threemojo_server/src/payments/google_play_api.dart';
import 'package:threemojo_server/src/payments/google_play_receipt_verifier.dart';
import 'package:threemojo_server/src/payments/receipt_verifier.dart';

Matcher _rejected(ReceiptRejection reason) => throwsA(
  isA<ReceiptRejectedException>().having((e) => e.reason, 'reason', reason),
);

const _claim = PurchaseClaim(
  platform: StorePlatform.android,
  productId: 'raen.unlock_2h',
  receipt: 'purchase-token-abc',
  transactionId: 'GPA.1234-5678-9012-34567',
);

/// Una `ProductPurchase` come la risponde Google.
Map<String, dynamic> _purchase({
  int purchaseState = 0,
  int consumptionState = 0,
  String orderId = 'GPA.1234-5678-9012-34567',
  String? productId = 'raen.unlock_2h',
}) => {
  'kind': 'androidpublisher#productPurchase',
  'purchaseTimeMillis': '1793000000000',
  'purchaseState': purchaseState,
  'consumptionState': consumptionState,
  'orderId': orderId,
  'acknowledgementState': 0,
  'purchaseType': 0,
  'productId': ?productId,
  'regionCode': 'IT',
};

class _FakeApi implements GooglePlayApi {
  _FakeApi(this.response);

  Map<String, dynamic> response;
  final consumed = <String>[];

  @override
  Future<Map<String, dynamic>> getProductPurchase({
    required String productId,
    required String purchaseToken,
  }) async => response;

  @override
  Future<void> consume({
    required String productId,
    required String purchaseToken,
  }) async => consumed.add('$productId/$purchaseToken');
}

void main() {
  group('GooglePlayReceiptVerifier', () {
    test('a purchased, not yet consumed product is verified and consumed on '
        'finalize', () async {
      final api = _FakeApi(_purchase());
      final verifier = GooglePlayReceiptVerifier(api: api);

      final verified = await verifier.verify(_claim);
      await verifier.finalize(verified);

      expect(verified.transactionKey, 'purchase-token-abc');
      expect(verified.productId, 'raen.unlock_2h');
      expect(
        verified.purchasedAt,
        DateTime.fromMillisecondsSinceEpoch(1793000000000, isUtc: true),
      );
      expect(verified.alreadyConsumed, isFalse);
      expect(verified.storeEnforcesSingleUse, isTrue);
      expect(api.consumed, ['raen.unlock_2h/purchase-token-abc']);
    });

    test('canceled or pending purchases are not paid', () async {
      for (final state in [1, 2]) {
        await expectLater(
          GooglePlayReceiptVerifier(
            api: _FakeApi(_purchase(purchaseState: state)),
          ).verify(_claim),
          _rejected(ReceiptRejection.notPurchased),
          reason: 'purchaseState $state',
        );
      }
    });

    test('an already consumed purchase is reported as such (the service '
        'decides with the registry)', () async {
      final verified = await GooglePlayReceiptVerifier(
        api: _FakeApi(_purchase(consumptionState: 1)),
      ).verify(_claim);

      expect(verified.alreadyConsumed, isTrue);
    });

    test('another order id or another product is caught', () async {
      await expectLater(
        GooglePlayReceiptVerifier(
          api: _FakeApi(_purchase(orderId: 'GPA.other')),
        ).verify(_claim),
        _rejected(ReceiptRejection.transactionMismatch),
      );
      final verified = await GooglePlayReceiptVerifier(
        api: _FakeApi(_purchase(productId: 'raen.something_else')),
      ).verify(_claim);
      expect(verified.productId, 'raen.something_else');
    });

    test('a response without the purchase time is invalid', () async {
      await expectLater(
        GooglePlayReceiptVerifier(
          api: _FakeApi(_purchase()..remove('purchaseTimeMillis')),
        ).verify(_claim),
        _rejected(ReceiptRejection.invalidReceipt),
      );
    });
  });

  group('GooglePlayApiImpl', () {
    GooglePlayApiImpl api(http.Client client) => GooglePlayApiImpl(
      packageName: 'it.ameol.raen',
      serviceAccountJson: '{}',
      clientFactory: () async => client,
    );

    test(
      'calls purchases.products.get and :consume on androidpublisher v3',
      () async {
        final calls = <String>[];
        final client = MockClient((request) async {
          calls.add('${request.method} ${request.url}');
          return http.Response(
            request.method == 'GET' ? '{"purchaseState": 0}' : '',
            200,
          );
        });

        await api(client).getProductPurchase(
          productId: 'raen.unlock_2h',
          purchaseToken: 'tok/en',
        );
        await api(
          client,
        ).consume(productId: 'raen.unlock_2h', purchaseToken: 'tok/en');

        const base =
            'https://androidpublisher.googleapis.com/androidpublisher/v3/'
            'applications/it.ameol.raen/purchases/products/raen.unlock_2h/'
            'tokens/tok%2Fen';
        expect(calls, ['GET $base', 'POST $base:consume']);
      },
    );

    test('404/410 → invalid receipt, 401/403 → not configured, 5xx → '
        'temporary', () async {
      for (final status in [404, 410]) {
        await expectLater(
          api(
            MockClient((_) async => http.Response('', status)),
          ).getProductPurchase(productId: 'p', purchaseToken: 't'),
          _rejected(ReceiptRejection.invalidReceipt),
        );
      }
      await expectLater(
        api(
          MockClient((_) async => http.Response('', 403)),
        ).getProductPurchase(productId: 'p', purchaseToken: 't'),
        throwsA(isA<StoreNotConfiguredException>()),
      );
      await expectLater(
        api(
          MockClient((_) async => http.Response('', 503)),
        ).consume(productId: 'p', purchaseToken: 't'),
        throwsA(isA<StoreUnavailableException>()),
      );
    });

    test('a service account that cannot authenticate is a configuration '
        'error', () async {
      final broken = GooglePlayApiImpl(
        packageName: 'it.ameol.raen',
        serviceAccountJson: '{}',
        clientFactory: () async => throw ArgumentError('bad key'),
      );

      await expectLater(
        broken.getProductPurchase(productId: 'p', purchaseToken: 't'),
        throwsA(isA<StoreNotConfiguredException>()),
      );
    });
  });
}
