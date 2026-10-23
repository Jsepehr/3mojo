import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../../routes/paywall/notifications/apple.dart' as apple;
import '../../../../routes/paywall/notifications/google.dart' as google;

class _MockRequestContext extends Mock implements RequestContext {}

/// Senza `PAYMENTS_MODE=real` e senza le variabili delle notifiche le route
/// non esistono: rispondono 404 a tutto, prima ancora di leggere il corpo.
void main() {
  RequestContext post(String path) {
    final context = _MockRequestContext();
    when(() => context.request).thenReturn(
      Request.post(
        Uri.parse('http://localhost$path'),
        body: '{"signedPayload": "x"}',
      ),
    );
    return context;
  }

  test('App Store Server Notifications are off by default', () async {
    final response = await apple.onRequest(
      post('/paywall/notifications/apple'),
    );

    expect(response.statusCode, HttpStatus.notFound);
  });

  test('Google Real-time Developer Notifications are off by default, even '
      'with a token', () async {
    final response = await google.onRequest(
      post('/paywall/notifications/google?token=${'x' * 40}'),
    );

    expect(response.statusCode, HttpStatus.notFound);
  });
}
