import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/constant_time.dart';
import 'package:threemojo_server/src/session_store.dart';

/// `GET /debug/sessions` — solo per test locali: elenca tutte le sessioni
/// in memoria, senza i filtri che il server applica alla lista "nearby" del
/// WebSocket `/ws` (raggio, genere, tempo di permanenza). Serve a
/// controllare "chi è arrivato al server" e se è connesso o nel periodo di
/// grazia, non cosa vede un client specifico. Niente distanze a coppie (con
/// quelle chiunque avesse il token potrebbe triangolare tutti).
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
  if (expectedToken.isEmpty ||
      !constantTimeEquals(providedToken, expectedToken)) {
    return Response(statusCode: HttpStatus.notFound);
  }

  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  return Response.json(body: SessionStore.instance.debugSnapshot());
}
