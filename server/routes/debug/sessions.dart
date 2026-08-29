import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/session_store.dart';

/// `GET /debug/sessions` — solo per test locali: elenca tutte le sessioni
/// online in memoria, senza i filtri che applica `/nearby` (raggio, genere,
/// tempo di permanenza). Serve a controllare "chi è arrivato al server",
/// non cosa vede un client specifico.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  return Response.json(body: SessionStore.instance.debugSnapshot());
}
