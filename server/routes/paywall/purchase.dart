import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/paywall_store.dart';

/// `POST /paywall/purchase` — `{"deviceId": "..."}`. Registra un nuovo
/// sblocco (finto: nessun pagamento vero verificato qui, vedi
/// `PurchaseUnlockUseCase` lato client) con l'ora **del server**, non del
/// client — è proprio questo il punto: un client non può falsificare
/// l'ora del server cambiando l'orologio del proprio telefono.
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

  final deviceId = body['deviceId'] as String?;
  if (deviceId == null || deviceId.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'deviceId è obbligatorio'},
    );
  }

  PaywallStore.instance.recordUnlock(deviceId);
  return Response(statusCode: 204);
}
