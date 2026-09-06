import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/paywall_store.dart';

/// `GET /paywall/status?deviceId=...` — lo sblocco di `deviceId` è ancora
/// valido (entro le 2 ore da `PaywallStore.unlockDuration`), calcolato con
/// l'ora del server.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final deviceId = context.request.uri.queryParameters['deviceId'];
  if (deviceId == null || deviceId.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'deviceId è obbligatorio'},
    );
  }

  return Response.json(
    body: {'isUnlocked': PaywallStore.instance.isUnlocked(deviceId)},
  );
}
