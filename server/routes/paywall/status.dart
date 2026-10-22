import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/paywall_store.dart';

/// `POST /paywall/status` — `{"unlockToken": "..."}`: lo sblocco è ancora
/// valido (entro le 2 ore da `PaywallStore.unlockDuration`), calcolato con
/// l'ora del server? Risponde `{"isUnlocked": bool, "remainingSeconds": int}`
/// — il tempo residuo sull'orologio del server (`0` se non vale), su cui il
/// client riallinea la scadenza che mostra a ogni controllo.
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

  // Un token che non è una stringa (numero, lista…) è una richiesta
  // sbagliata, non un errore del server: mai un cast che esplode in un 500.
  final rawToken = body['unlockToken'];
  if (rawToken != null && rawToken is! String) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'unlockToken non valido'},
    );
  }
  final token = rawToken is String ? rawToken : '';
  final remainingSeconds = token.isEmpty
      ? 0
      : PaywallStore.instance.remainingSecondsFor(token);
  return Response.json(
    body: {
      // Sull'ultimo secondo `remainingSeconds` è già 0: "sbloccato" segue lo
      // stesso numero, così le due cose non si contraddicono mai.
      'isUnlocked': remainingSeconds > 0,
      'remainingSeconds': remainingSeconds,
    },
  );
}
