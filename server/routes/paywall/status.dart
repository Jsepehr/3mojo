import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/paywall_store.dart';

/// `POST /paywall/status` — `{"unlockToken": "..."}`: lo sblocco è ancora
/// valido (entro le 2 ore da `PaywallStore.unlockDuration`), calcolato con
/// l'ora del server?
///
/// POST e non GET apposta: il token viaggia nel corpo, non nell'URL — gli
/// URL finiscono per default nei log di proxy e provider.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final Object? body;
  try {
    body = await context.request.json();
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'JSON non valido'});
  }
  if (body is! Map<String, dynamic>) {
    return Response.json(statusCode: 400, body: {'error': 'JSON non valido'});
  }

  final token = body['unlockToken'] as String? ?? '';
  return Response.json(
    body: {
      'isUnlocked': token.isNotEmpty && PaywallStore.instance.isUnlocked(token),
    },
  );
}
