import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:threemojo_server/src/paywall_store.dart';

import '../../../routes/paywall/purchase.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _MockConnectionInfo extends Mock implements HttpConnectionInfo {}

Future<Response> _post({String ip = '203.0.113.7'}) {
  final context = _MockRequestContext();
  final request = _MockRequest();
  final connectionInfo = _MockConnectionInfo();
  when(() => connectionInfo.remoteAddress).thenReturn(InternetAddress(ip));
  when(() => request.method).thenReturn(HttpMethod.post);
  when(() => request.headers).thenReturn(const {});
  when(() => request.connectionInfo).thenReturn(connectionInfo);
  when(() => context.request).thenReturn(request);
  return route.onRequest(context);
}

void main() {
  group('POST /paywall/purchase', () {
    test(
      'returns a token and the remaining time on the server clock',
      () async {
        final response = await _post();

        expect(response.statusCode, HttpStatus.ok);
        final body = await response.json() as Map<String, dynamic>;
        final token = body['unlockToken'] as String;
        expect(PaywallStore.instance.isUnlocked(token), isTrue);
        expect(body['expiresInSeconds'], PaywallStore.unlockDuration.inSeconds);
        // Appena emesso: il residuo è (quasi) l'intera durata, mai di più.
        final remaining = body['remainingSeconds'] as int;
        expect(remaining, lessThanOrEqualTo(7200));
        expect(remaining, greaterThanOrEqualTo(7199));
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
