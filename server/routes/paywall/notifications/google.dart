import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/constant_time.dart';
import 'package:threemojo_server/src/payments/payments.dart';
import 'package:threemojo_server/src/payments/store_notifications.dart';

/// `POST /paywall/notifications/google?token=<GOOGLE_RTDN_TOKEN>` — Google
/// Play Real-time Developer Notifications via push di Pub/Sub
/// (`GoogleNotificationHandler`): su un rimborso/annullamento revoca lo
/// sblocco dell'acquisto.
///
/// **Spenta di default** (404): si accende con `PAYMENTS_MODE=real`,
/// configurazione Google completa e `GOOGLE_RTDN_TOKEN` (≥ 32 caratteri,
/// es. `openssl rand -hex 32`), lo stesso messo nell'URL della
/// sottoscrizione push. Token sbagliato o assente → 404, come spenta.
///
/// 200 per ogni notifica autentica (Pub/Sub altrimenti la rimanda), 400 se
/// malformata.
Future<Response> onRequest(RequestContext context) async {
  final handler = Payments.instance.googleNotifications;
  final expected = Payments.instance.config.google?.rtdnToken;
  if (handler == null || expected == null) return Response(statusCode: 404);
  final token = context.request.uri.queryParameters['token'] ?? '';
  if (!constantTimeEquals(token, expected)) return Response(statusCode: 404);
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
