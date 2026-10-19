import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:threemojo_server/src/paywall_store.dart';

import '../../../routes/paywall/status.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

Future<Response> _post(Object? body) {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request.post(
      Uri.parse('http://localhost/paywall/status'),
      body: body is String ? body : jsonEncode(body),
    ),
  );
  return route.onRequest(context);
}

void main() {
  group('POST /paywall/status', () {
    test('an unlockToken that is not a string is a 400, never a 500', () async {
      for (final token in [
        42,
        true,
        ['tok'],
        {'a': 1},
      ]) {
        final response = await _post({'unlockToken': token});

        expect(response.statusCode, HttpStatus.badRequest, reason: '$token');
        expect(await response.json(), {'error': 'unlockToken non valido'});
      }
    });

    test('a missing or unknown token is simply not unlocked', () async {
      for (final body in [
        <String, dynamic>{},
        {'unlockToken': 'nope'},
      ]) {
        final response = await _post(body);

        expect(response.statusCode, HttpStatus.ok);
        expect(await response.json(), {'isUnlocked': false});
      }
    });

    test('a token issued by the server is unlocked', () async {
      final token = PaywallStore.instance.issueUnlockToken();

      final response = await _post({'unlockToken': token});

      expect(await response.json(), {'isUnlocked': true});
    });

    test('a body that is not a JSON object is a 400', () async {
      expect((await _post('[1, 2]')).statusCode, HttpStatus.badRequest);
      expect((await _post('{')).statusCode, HttpStatus.badRequest);
    });

    test('only POST is accepted', () async {
      final context = _MockRequestContext();
      when(
        () => context.request,
      ).thenReturn(Request.get(Uri.parse('http://localhost/paywall/status')));

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
