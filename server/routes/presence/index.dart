import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/session_store.dart';

/// `POST /presence` per mandare la propria posizione (equivalente di andare
/// online / muoversi), `DELETE /presence?sessionId=...` per uscire (End).
Future<Response> onRequest(RequestContext context) async {
  switch (context.request.method) {
    case HttpMethod.post:
      return _upsertPresence(context);
    case HttpMethod.delete:
      return _removePresence(context);
    default:
      return Response(statusCode: 405);
  }
}

Future<Response> _upsertPresence(RequestContext context) async {
  final Object? body;
  try {
    body = await context.request.json();
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'JSON non valido'});
  }

  if (body is! Map<String, dynamic>) {
    return Response.json(statusCode: 400, body: {'error': 'JSON non valido'});
  }

  final sessionId = body['sessionId'] as String?;
  final lat = (body['lat'] as num?)?.toDouble();
  final lng = (body['lng'] as num?)?.toDouble();

  if (sessionId == null || sessionId.isEmpty || lat == null || lng == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'sessionId, lat e lng sono obbligatori'},
    );
  }

  SessionStore.instance.upsertPosition(
    sessionId: sessionId,
    lat: lat,
    lng: lng,
  );
  return Response(statusCode: 204);
}

Future<Response> _removePresence(RequestContext context) async {
  final sessionId = context.request.uri.queryParameters['sessionId'];
  if (sessionId == null || sessionId.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'sessionId è obbligatorio'},
    );
  }

  SessionStore.instance.remove(sessionId);
  return Response(statusCode: 204);
}
