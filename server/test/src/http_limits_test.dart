import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';
import 'package:threemojo_server/src/connection_limit.dart';
import 'package:threemojo_server/src/cors_policy.dart';
import 'package:threemojo_server/src/http_limits.dart';

Request _post(Object body, {Map<String, String> headers = const {}}) =>
    Request.post(
      Uri.parse('http://localhost/x'),
      body: body is String ? body : jsonEncode(body),
      headers: headers,
    );

void main() {
  group('readJsonBody', () {
    test('reads a normal body', () async {
      expect(await readJsonBody(_post({'a': 1})), {'a': 1});
    });

    test(
      'a body over the limit is refused, by Content-Length or by counting',
      () async {
        final big = 'x' * (maxHttpBodyBytes + 1);
        await expectLater(
          readJsonBody(_post(jsonEncode({'a': big}))),
          throwsA(isA<BodyTooLargeException>()),
        );
        // A lying/missing Content-Length does not help: bytes are counted.
        await expectLater(
          readJsonBody(
            _post(jsonEncode({'a': 'y' * 200}), headers: {}),
            maxBytes: 100,
          ),
          throwsA(isA<BodyTooLargeException>()),
        );
      },
    );

    test('not JSON is a FormatException, not a 500', () async {
      await expectLater(
        readJsonBody(_post('not json')),
        throwsA(isA<FormatException>()),
      );
    });

    test('the 413 response is JSON with a code', () async {
      final response = bodyTooLargeResponse();
      expect(response.statusCode, 413);
      expect((await response.json() as Map)['code'], 'bodyTooLarge');
    });
  });

  group('WebSocketConnectionLimit', () {
    test('refuses over the cap and frees a place on release', () {
      final limit = WebSocketConnectionLimit(max: 2);
      expect(limit.tryAcquire(), isTrue);
      expect(limit.tryAcquire(), isTrue);
      expect(limit.hasRoom, isFalse);
      expect(limit.tryAcquire(), isFalse);
      limit.release();
      expect(limit.hasRoom, isTrue);
      expect(limit.tryAcquire(), isTrue);
      expect(limit.active, 2);
    });

    test('release never goes below zero; env var with a sane default', () {
      final limit = WebSocketConnectionLimit(max: 1)..release();
      expect(limit.active, 0);
      expect(
        WebSocketConnectionLimit.fromEnvironment({}).max,
        WebSocketConnectionLimit.defaultMax,
      );
      expect(
        WebSocketConnectionLimit.fromEnvironment({
          'MAX_WS_CONNECTIONS': '50',
        }).max,
        50,
      );
      expect(
        WebSocketConnectionLimit.fromEnvironment({
          'MAX_WS_CONNECTIONS': '-3',
        }).max,
        WebSocketConnectionLimit.defaultMax,
      );
    });
  });

  group('CorsPolicy', () {
    test('development: any origin; production: no CORS at all', () {
      expect(
        CorsPolicy.fromEnvironment({}).headersFor('http://localhost:5000'),
        containsPair('Access-Control-Allow-Origin', '*'),
      );
      expect(
        CorsPolicy.fromEnvironment({
          'RAEN_ENV': 'production',
        }).headersFor('https://evil.example'),
        isEmpty,
      );
    });

    test('an allow-list echoes only listed origins', () {
      final policy = CorsPolicy.fromEnvironment({
        'RAEN_ENV': 'production',
        'CORS_ALLOW_ORIGIN': 'https://raen.example, https://app.raen.example',
      });
      final ok = policy.headersFor('https://raen.example');
      expect(ok['Access-Control-Allow-Origin'], 'https://raen.example');
      expect(ok['Vary'], 'Origin');
      expect(policy.headersFor('https://evil.example'), isEmpty);
      expect(policy.headersFor(null), isEmpty);
    });

    test(
      '"none" turns it off, "*" forces it; Authorization is never allowed',
      () {
        expect(
          CorsPolicy.fromEnvironment({
            'CORS_ALLOW_ORIGIN': 'none',
          }).headersFor('x'),
          isEmpty,
        );
        final star = CorsPolicy.fromEnvironment({
          'RAEN_ENV': 'production',
          'CORS_ALLOW_ORIGIN': '*',
        }).headersFor('https://a.example');
        expect(star['Access-Control-Allow-Origin'], '*');
        expect(
          star['Access-Control-Allow-Headers'],
          isNot(contains('Authorization')),
        );
      },
    );
  });
}
