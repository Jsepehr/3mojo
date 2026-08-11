import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/session_store.dart';

/// `GET /nearby?sessionId=...&radiusMeters=100` — persone entro il raggio
/// dalla posizione già nota di `sessionId` (mandata prima con `POST
/// /presence`), con distanza e probabilità d'incontro già calcolate: il
/// client non riceve mai le posizioni grezze di nessuno.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final query = context.request.uri.queryParameters;
  final sessionId = query['sessionId'];
  if (sessionId == null || sessionId.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'sessionId è obbligatorio'},
    );
  }

  final radiusMeters = double.tryParse(query['radiusMeters'] ?? '') ?? 100;

  final people = SessionStore.instance.nearbyPeople(
    sessionId: sessionId,
    radiusMeters: radiusMeters,
  );

  if (people == null) {
    return Response.json(
      statusCode: 404,
      body: {
        'error':
            'Nessuna posizione nota per questo sessionId — '
            'chiama prima POST /presence',
      },
    );
  }

  return Response.json(body: people.map((p) => p.toJson()).toList());
}
