import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:threemojo_server/src/session_store.dart';

import '../../../routes/presence/index.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

void main() {
  group('POST /presence', () {
    test('204s and stores the position on valid input', () async {
      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.post);
      when(request.json).thenAnswer(
        (_) async => {'sessionId': 'presence-test-1', 'lat': 41.9, 'lng': 12.5},
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, equals(HttpStatus.noContent));
      expect(
        SessionStore.instance.nearbyPeople(
          sessionId: 'presence-test-1',
          radiusMeters: 1,
        ),
        isNotNull,
      );
    });

    test('400s when a required field is missing', () async {
      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.post);
      when(request.json).thenAnswer((_) async => {'sessionId': 'no-coords'});

      final response = await route.onRequest(context);

      expect(response.statusCode, equals(HttpStatus.badRequest));
    });
  });

  group('DELETE /presence', () {
    test('204s and removes a known session', () async {
      SessionStore.instance.upsertPosition(
        sessionId: 'presence-test-remove',
        lat: 0,
        lng: 0,
      );

      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.delete);
      when(
        () => request.uri,
      ).thenReturn(Uri.parse('/presence?sessionId=presence-test-remove'));

      final response = await route.onRequest(context);

      expect(response.statusCode, equals(HttpStatus.noContent));
    });

    test('400s without a sessionId', () async {
      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.delete);
      when(() => request.uri).thenReturn(Uri.parse('/presence'));

      final response = await route.onRequest(context);

      expect(response.statusCode, equals(HttpStatus.badRequest));
    });
  });

  test('rejects methods other than POST/DELETE', () async {
    final context = _MockRequestContext();
    final request = _MockRequest();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.put);

    final response = await route.onRequest(context);

    expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
  });
}
