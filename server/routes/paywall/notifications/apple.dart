import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/payments/payments.dart';
import 'package:threemojo_server/src/payments/store_notifications.dart';

/// `POST /paywall/notifications/apple` — App Store Server Notifications v2
/// (`AppleNotificationHandler`): su un rimborso revoca lo sblocco della
/// transazione.
///
/// **Spenta di default** (404): si accende con `PAYMENTS_MODE=real`,
/// configurazione Apple completa e `APPLE_NOTIFICATIONS_ENABLED=true`.
/// L'autenticità la dà la firma Apple del corpo (JWS), non l'URL.
///
/// 200 per ogni notifica autentica (anche se non serve a nulla: Apple
/// altrimenti la rimanda per giorni), 400 se non è firmata da Apple.
Future<Response> onRequest(RequestContext context) async {
  final handler = Payments.instance.appleNotifications;
  if (handler == null) return Response(statusCode: 404);
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }
  final Object? body;
  try {
    body = await context.request.json();
  } catch (_) {
    return Response(statusCode: 400);
  }
  final outcome = await handler.handle(body);
  return Response(
    statusCode: outcome == NotificationOutcome.invalid ? 400 : 200,
  );
}
