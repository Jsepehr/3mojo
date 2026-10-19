import 'package:dart_frog/dart_frog.dart';

/// `GET /` — controllo di salute per il load balancer / il monitoraggio:
/// risponde solo che il servizio è vivo, senza nessun dato sulle sessioni.
Response onRequest(RequestContext context) {
  return Response.json(body: {'service': '3mojo', 'status': 'ok'});
}
