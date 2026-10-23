import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:threemojo_server/src/payments/fake_receipt_verifier.dart';
import 'package:threemojo_server/src/paywall_store.dart';

import '../../../routes/paywall/purchase.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _MockConnectionInfo extends Mock implements HttpConnectionInfo {}

/// Ogni test usa un IP diverso: il limite per IP (10 ogni 10 minuti) è
/// condiviso dal processo.
var _nextIp = 1;

Future<Response> _post(Object? body) {
  final context = _MockRequestContext();
  final request = _MockRequest();
  final connectionInfo = _MockConnectionInfo();
  when(
    () => connectionInfo.remoteAddress,
  ).thenReturn(InternetAddress('203.0.113.${_nextIp++}'));
  when(() => request.method).thenReturn(HttpMethod.post);
  when(() => request.headers).thenReturn(const {});
  when(() => request.connectionInfo).thenReturn(connectionInfo);
  when(
    request.json,
  ).thenAnswer((_) async => body is String ? jsonDecode(body) : body);
  when(() => context.request).thenReturn(request);
  return route.onRequest(context);
}

Future<Map<String, Object?>> _fakePurchase(String transactionId) async => {
  'platform': 'fake',
  'productId': FakeReceiptVerifier.productId,
  'receipt': await FakeReceiptVerifier.buildReceipt(
    transactionId: transactionId,
    purchasedAt: DateTime.now(),
  ),
  'transactionId': transactionId,
};

/// I test girano senza `PAYMENTS_MODE`: modalità finta, come in sviluppo.
void main() {
  group('POST /paywall/purchase', () {
    test('a verified (simulated) purchase returns a token and the remaining '
        'time on the server clock', () async {
      final response = await _post(await _fakePurchase('route-tx-1'));

      expect(response.statusCode, HttpStatus.ok);
      final body = await response.json() as Map<String, dynamic>;
      final token = body['unlockToken'] as String;
      expect(PaywallStore.instance.isUnlocked(token), isTrue);
      expect(body['expiresInSeconds'], PaywallStore.unlockDuration.inSeconds);
      expect(body['remainingSeconds'], inInclusiveRange(7199, 7200));
      expect(body['alreadyRedeemed'], isFalse);
    });

    test('the same transaction again gets the same token, never a second '
        'unlock', () async {
      final purchase = await _fakePurchase('route-tx-2');

      final first = await (await _post(purchase)).json() as Map;
      final second = await _post(purchase);

      expect(second.statusCode, HttpStatus.ok);
      final body = await second.json() as Map;
      expect(body['unlockToken'], first['unlockToken']);
      expect(body['alreadyRedeemed'], isTrue);
    });

    test('without a receipt there is no unlock anymore (400)', () async {
      for (final body in [
        <String, Object?>{},
        {'platform': 'fake', 'productId': FakeReceiptVerifier.productId},
        {'platform': 'nfc', 'productId': 'x', 'receipt': 'y'},
        {'platform': 'fake', 'productId': 1, 'receipt': 'y'},
        '[1]',
      ]) {
        final response = await _post(body);

        expect(response.statusCode, HttpStatus.badRequest, reason: '$body');
        expect((await response.json() as Map)['code'], 'invalidRequest');
      }
    });

    test('a forged or wrong-product receipt is 422 with the reason', () async {
      final purchase = await _fakePurchase('route-tx-3');
      final forged = {...purchase, 'receipt': '${purchase['receipt']}x'};
      final wrongProduct = {...purchase, 'productId': 'raen.other'};

      final forgedResponse = await _post(forged);
      final wrongResponse = await _post(wrongProduct);

      expect(forgedResponse.statusCode, HttpStatus.unprocessableEntity);
      expect((await forgedResponse.json() as Map)['code'], 'invalidReceipt');
      expect(wrongResponse.statusCode, HttpStatus.unprocessableEntity);
      expect((await wrongResponse.json() as Map)['code'], 'wrongProduct');
    });

    test(
      'real platforms are not enabled in fake mode (503, no token)',
      () async {
        for (final platform in ['ios', 'android']) {
          final response = await _post({
            'platform': platform,
            'productId': 'raen.unlock_2h',
            'receipt': 'anything',
            'transactionId': '1',
          });

          expect(response.statusCode, HttpStatus.serviceUnavailable);
          final body = await response.json() as Map;
          expect(body['code'], 'platformNotEnabled');
          expect(body.containsKey('unlockToken'), isFalse);
        }
      },
    );

    test('only POST is accepted', () async {
      final context = _MockRequestContext();
      when(
        () => context.request,
      ).thenReturn(Request.get(Uri.parse('http://localhost/paywall/purchase')));

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
