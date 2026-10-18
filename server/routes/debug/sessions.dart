import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/session_store.dart';

/// `GET /debug/sessions` — solo per test locali: elenca tutte le sessioni
/// online in memoria, senza i filtri che applica `/nearby` (raggio, genere,
/// tempo di permanenza). Serve a controllare "chi è arrivato al server",
/// non cosa vede un client specifico.
///
/// **Spento di default.** Si accende solo avviando il server con la
/// variabile d'ambiente `DEBUG_ENDPOINTS_TOKEN`, e risponde solo a chi manda
/// lo stesso valore nell'header `X-Debug-Token`. In ogni altro caso risponde
/// 404, come se non esistesse. Prima era pubblico: chiunque conoscesse
/// l'indirizzo vedeva le distanze reciproche tra tutte le persone online
/// (quindi poteva triangolarle) e il loro genere e preferenza.
Response onRequest(RequestContext context) {
  final expectedToken = Platform.environment['DEBUG_ENDPOINTS_TOKEN'] ?? '';
  final providedToken = context.request.headers['x-debug-token'] ?? '';
  if (expectedToken.isEmpty || !_constantTimeEquals(providedToken, expectedToken)) {
    return Response(statusCode: HttpStatus.notFound);
  }

  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  return Response.json(body: SessionStore.instance.debugSnapshot());
}

/// Confronto che non si ferma al primo carattere diverso: il tempo di
/// risposta non rivela quanta parte del token è giusta.
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
