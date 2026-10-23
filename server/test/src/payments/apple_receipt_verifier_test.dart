import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:threemojo_server/src/payments/app_store_server_api.dart';
import 'package:threemojo_server/src/payments/apple_jws_verifier.dart';
import 'package:threemojo_server/src/payments/apple_receipt_verifier.dart';
import 'package:threemojo_server/src/payments/ecdsa.dart';
import 'package:threemojo_server/src/payments/payments_config.dart';
import 'package:threemojo_server/src/payments/receipt_verifier.dart';

import 'test_pki.dart';

Matcher _rejected(ReceiptRejection reason) => throwsA(
  isA<ReceiptRejectedException>().having((e) => e.reason, 'reason', reason),
);

AppleStoreSettings _settings(
  TestAppleChain chain, {
  AppleEnvironment environment = AppleEnvironment.sandbox,
}) => AppleStoreSettings(
  bundleId: 'it.ameol.raen',
  productId: 'raen.unlock_2h',
  environment: environment,
  trustedRoots: [chain.root],
);

PurchaseClaim _claim(
  String receipt, {
  String transactionId = '2000000123456789',
}) => PurchaseClaim(
  platform: StorePlatform.ios,
  productId: 'raen.unlock_2h',
  receipt: receipt,
  transactionId: transactionId,
);

void main() {
  late TestAppleChain chain;

  setUp(() => chain = TestAppleChain());

  group('AppleReceiptVerifier (signed StoreKit 2 transaction)', () {
    test('a valid consumable transaction is verified, with the signed '
        'product and purchase date', () async {
      final purchasedAt = DateTime.utc(2026, 10, 23, 10);
      final verifier = AppleReceiptVerifier(settings: _settings(chain));

      final verified = await verifier.verify(
        _claim(chain.signJws(appleTransaction(purchaseDate: purchasedAt))),
      );

      expect(verified.platform, StorePlatform.ios);
      expect(verified.transactionKey, '2000000123456789');
      expect(verified.productId, 'raen.unlock_2h');
      expect(verified.purchasedAt, purchasedAt);
      expect(verified.storeEnforcesSingleUse, isFalse);
    });

    test('another app (bundle id) is rejected', () async {
      final verifier = AppleReceiptVerifier(settings: _settings(chain));

      await expectLater(
        verifier.verify(
          _claim(chain.signJws(appleTransaction(bundleId: 'com.other.app'))),
        ),
        _rejected(ReceiptRejection.wrongApp),
      );
    });

    test('a bad signature is rejected', () async {
      final verifier = AppleReceiptVerifier(settings: _settings(chain));
      final jws = chain.signJws(
        appleTransaction(),
        signWith: TestKey(EcCurve.p256, BigInt.from(4242)),
      );

      await expectLater(
        verifier.verify(_claim(jws)),
        _rejected(ReceiptRejection.invalidReceipt),
      );
    });

    test(
      'sandbox server: production transactions are rejected; production '
      'server: sandbox ones are accepted (App Review buys in sandbox)',
      () async {
        final sandbox = AppleReceiptVerifier(settings: _settings(chain));
        final production = AppleReceiptVerifier(
          settings: _settings(chain, environment: AppleEnvironment.production),
        );

        await expectLater(
          sandbox.verify(
            _claim(chain.signJws(appleTransaction(environment: 'Production'))),
          ),
          _rejected(ReceiptRejection.wrongEnvironment),
        );
        expect(
          (await production.verify(
            _claim(chain.signJws(appleTransaction())),
          )).transactionKey,
          '2000000123456789',
        );
        await expectLater(
          production.verify(
            _claim(chain.signJws(appleTransaction(environment: 'Xcode'))),
          ),
          _rejected(ReceiptRejection.wrongEnvironment),
        );
      },
    );

    test(
      'refunded, non-consumable or another transaction id are rejected',
      () async {
        final verifier = AppleReceiptVerifier(settings: _settings(chain));

        await expectLater(
          verifier.verify(
            _claim(chain.signJws(appleTransaction(revocationDate: 1))),
          ),
          _rejected(ReceiptRejection.refunded),
        );
        await expectLater(
          verifier.verify(
            _claim(chain.signJws(appleTransaction(type: 'Non-Consumable'))),
          ),
          _rejected(ReceiptRejection.wrongProduct),
        );
        await expectLater(
          verifier.verify(
            _claim(chain.signJws(appleTransaction()), transactionId: '1'),
          ),
          _rejected(ReceiptRejection.transactionMismatch),
        );
      },
    );

    test('a receipt that is not a signed transaction, without API '
        'credentials, is a configuration error — never accepted', () async {
      final verifier = AppleReceiptVerifier(settings: _settings(chain));

      await expectLater(
        verifier.verify(_claim('MIIT...base64-app-receipt')),
        throwsA(isA<StoreNotConfiguredException>()),
      );
    });
  });

  group('AppStoreServerApi (Get Transaction Info)', () {
    final apiKey = TestKey(EcCurve.p256, BigInt.from(0x5eed));
    const credentials = (issuerId: 'issuer-uuid', keyId: 'ABC123DEFG');

    AppStoreServerApi api(
      http.Client client, {
      AppleEnvironment environment = AppleEnvironment.sandbox,
    }) => AppStoreServerApi(
      credentials: AppleApiCredentials(
        issuerId: credentials.issuerId,
        keyId: credentials.keyId,
        privateKeyPem: apiKey.toPkcs8Pem(),
      ),
      bundleId: 'it.ameol.raen',
      environment: environment,
      client: client,
      now: () => DateTime.utc(2026, 10, 23, 12),
    );

    test('the bearer JWT is ES256 with kid/iss/aud/bid and verifies with the '
        '.p8 public key', () {
      final token = api(
        MockClient((_) async => http.Response('', 500)),
      ).buildToken();
      final parts = token.split('.');
      Map<String, dynamic> decode(String part) =>
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))))
              as Map<String, dynamic>;

      expect(decode(parts[0]), {
        'alg': 'ES256',
        'kid': 'ABC123DEFG',
        'typ': 'JWT',
      });
      final payload = decode(parts[1]);
      expect(payload['iss'], 'issuer-uuid');
      expect(payload['aud'], 'appstoreconnect-v1');
      expect(payload['bid'], 'it.ameol.raen');
      expect((payload['exp'] as int) - (payload['iat'] as int), 300);
      final publicKey = EcPublicKey(EcCurve.p256, apiKey.publicPoint);
      expect(
        publicKey.verifyJose(
          Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}')),
          base64Url.decode(base64Url.normalize(parts[2])),
          EcdsaHash.sha256,
        ),
        isTrue,
      );
    });

    test('without the JWS, the verifier asks Apple for the transaction and '
        'verifies what Apple signed', () async {
      final requested = <Uri>[];
      final client = MockClient((request) async {
        requested.add(request.url);
        expect(request.headers['authorization'], startsWith('Bearer '));
        return http.Response(
          jsonEncode({
            'signedTransactionInfo': chain.signJws(appleTransaction()),
          }),
          200,
        );
      });
      final verifier = AppleReceiptVerifier(
        settings: _settings(chain),
        api: api(client),
      );

      final verified = await verifier.verify(_claim('legacy-receipt'));

      expect(verified.transactionKey, '2000000123456789');
      expect(
        requested.single.toString(),
        'https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/2000000123456789',
      );
    });

    test('production: on 404 it tries sandbox; unknown in both is an '
        'invalid receipt', () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        return http.Response('{}', 404);
      });

      await expectLater(
        api(
          client,
          environment: AppleEnvironment.production,
        ).getSignedTransaction('2000000123456789'),
        _rejected(ReceiptRejection.invalidReceipt),
      );
      expect(hosts, [
        'api.storekit.itunes.apple.com',
        'api.storekit-sandbox.itunes.apple.com',
      ]);
    });

    test('401 is a configuration error, 5xx and network errors are '
        'temporary, a non-numeric id never leaves the server', () async {
      await expectLater(
        api(
          MockClient((_) async => http.Response('', 401)),
        ).getSignedTransaction('1'),
        throwsA(isA<StoreNotConfiguredException>()),
      );
      await expectLater(
        api(
          MockClient((_) async => http.Response('', 503)),
        ).getSignedTransaction('1'),
        throwsA(isA<StoreUnavailableException>()),
      );
      await expectLater(
        api(
          MockClient((_) async => throw http.ClientException('down')),
        ).getSignedTransaction('1'),
        throwsA(isA<StoreUnavailableException>()),
      );
      var called = false;
      await expectLater(
        api(
          MockClient((_) async {
            called = true;
            return http.Response('', 200);
          }),
        ).getSignedTransaction('../../admin'),
        _rejected(ReceiptRejection.invalidReceipt),
      );
      expect(called, isFalse);
    });

    test('a JWS from the API that is not signed by a trusted chain is '
        'rejected', () async {
      final other = TestAppleChain(
        rootKey: TestKey(EcCurve.p384, BigInt.from(31337)),
      );
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'signedTransactionInfo': other.signJws(appleTransaction()),
          }),
          200,
        ),
      );
      final verifier = AppleReceiptVerifier(
        settings: _settings(chain),
        api: api(client),
        jwsVerifier: AppleJwsVerifier(trustedRoots: [chain.root]),
      );

      await expectLater(
        verifier.verify(_claim('legacy-receipt')),
        _rejected(ReceiptRejection.invalidReceipt),
      );
    });
  });
}
