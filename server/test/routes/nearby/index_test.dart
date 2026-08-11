import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:threemojo_server/src/session_store.dart';

import '../../../routes/nearby/index.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

void main() {
  group('GET /nearby', () {
    test('200s with the nearby list for a known sessionId', () async {
      SessionStore.instance.upsertPosition(
        sessionId: 'nearby-test-me',
        lat: 0,
        lng: 0,
      );

      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.get);
      when(() => request.uri).thenReturn(
        Uri.parse('/nearby?sessionId=nearby-test-me&radiusMeters=100'),
      );

      final response = route.onRequest(context);

      expect(response.statusCode, equals(HttpStatus.ok));
      final body = jsonDecode(await response.body()) as List<dynamic>;
      expect(body, isA<List<dynamic>>());
    });

    test('404s when sessionId never sent a position', () {
      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.get);
      when(
        () => request.uri,
      ).thenReturn(Uri.parse('/nearby?sessionId=never-seen'));

      final response = route.onRequest(context);

      expect(response.statusCode, equals(HttpStatus.notFound));
    });

    test('400s without a sessionId', () {
      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.get);
      when(() => request.uri).thenReturn(Uri.parse('/nearby'));

      final response = route.onRequest(context);

      expect(response.statusCode, equals(HttpStatus.badRequest));
    });

    test('rejects methods other than GET', () {
      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.post);

      final response = route.onRequest(context);

      expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
    });
  });
}
