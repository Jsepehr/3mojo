import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/encounter_store.dart';
import 'package:threemojo_server/src/session_store.dart';

/// `GET /ws?sessionId=...`, upgradato a WebSocket — un solo canale
/// persistente per sessione porta presenza/vicinanze, richieste d'incontro
/// **e** i messaggi di chat, spinti dal server appena cambia qualcosa
/// invece che richiesti dal client a intervalli.
///
/// Messaggi in arrivo dal client, un JSON per riga, distinti da `"type"`:
/// - `{"type": "presence", "lat": ..., "lng": ..., "gender": ...,
///   "genderPreference": ..., "selfieBase64": ...}` — mandato alla
///   connessione e poi ogni volta che la posizione va aggiornata;
/// - `{"type": "sendEncounterRequest", "toSessionId": ...}`;
/// - `{"type": "respondToEncounterRequest", "requestId": ..., "accepted": bool}`;
/// - `{"type": "endMatch", "requestId": ...}`;
/// - `{"type": "chatMessage", "toSessionId": ..., "text": ..., "sentAt": ...}`
///   — inoltrato al destinatario se online, non conservato da nessuna
///   parte (il server fa solo da postino: se il destinatario non è
///   connesso in questo momento, il messaggio va perso).
///
/// Messaggi in uscita verso il client:
/// - `{"type": "nearby", "people": [...]}`;
/// - `{"type": "encounters", "incoming": [...], "outgoing": [...]}` — mandato
///   subito alla connessione (con lo stato già esistente, utile dopo una
///   riconnessione) e di nuovo a ogni cambiamento che riguarda la sessione;
/// - `{"type": "chatMessage", "fromSessionId": ..., "text": ..., "sentAt": ...}`.
///
/// Quando il socket si chiude (pulito o no): la sessione viene rimossa
/// subito da `SessionStore` (niente più sessioni fantasma), e le sue
/// richieste d'incontro ancora pendenti vengono cancellate (chi le aveva
/// mandate/ricevute non potrebbe comunque mai ottenere risposta).
Future<Response> onRequest(RequestContext context) async {
  final sessionId = context.request.uri.queryParameters['sessionId'];
  if (sessionId == null || sessionId.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'sessionId è obbligatorio'},
    );
  }

  SessionStore.instance.startAutoPurge(
    onPurged: (removedIds) {
      for (final id in removedIds) {
        ConnectionHub.instance.unregister(id);
      }
      ConnectionHub.instance.broadcastNearbyUpdates();
    },
  );

  final handler = fromShelfHandler(
    webSocketHandler((webSocket, protocol) {
      ConnectionHub.instance.register(sessionId, webSocket.sink);
      // Stato già esistente (es. richieste ricevute prima di una
      // riconnessione) — non aspettare il prossimo cambiamento per vederlo.
      ConnectionHub.instance.pushEncounterSnapshot(sessionId);

      webSocket.stream.listen(
        (raw) {
          final Object? decoded;
          try {
            decoded = jsonDecode(raw as String);
          } catch (_) {
            return;
          }
          if (decoded is! Map<String, dynamic>) return;

          switch (decoded['type']) {
            case 'presence':
              _handlePresence(sessionId, decoded);
            case 'sendEncounterRequest':
              _handleSendEncounterRequest(sessionId, decoded);
            case 'respondToEncounterRequest':
              _handleRespondToEncounterRequest(sessionId, decoded);
            case 'endMatch':
              _handleEndMatch(sessionId, decoded);
            case 'chatMessage':
              _handleChatMessage(sessionId, decoded);
          }
        },
        onDone: () {
          SessionStore.instance.remove(sessionId);
          ConnectionHub.instance.unregister(sessionId);
          ConnectionHub.instance.broadcastNearbyUpdates();

          final affected = EncounterStore.instance.cancelAllPendingFor(
            sessionId,
          );
          for (final request in affected) {
            ConnectionHub.instance.pushEncounterSnapshot(
              request.otherSessionId(sessionId),
            );
          }
        },
      );
    }),
  );

  return handler(context);
}

void _handlePresence(String sessionId, Map<String, dynamic> decoded) {
  final lat = (decoded['lat'] as num?)?.toDouble();
  final lng = (decoded['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return;

  SessionStore.instance.upsertPosition(
    sessionId: sessionId,
    lat: lat,
    lng: lng,
    gender: decoded['gender'] as String? ?? 'unspecified',
    genderPreference: decoded['genderPreference'] as String? ?? 'everyone',
    selfieBase64: decoded['selfieBase64'] as String? ?? '',
  );
  ConnectionHub.instance.broadcastNearbyUpdates();
}

void _handleSendEncounterRequest(
  String sessionId,
  Map<String, dynamic> decoded,
) {
  final toSessionId = decoded['toSessionId'] as String?;
  if (toSessionId == null || toSessionId.isEmpty) return;

  EncounterStore.instance.sendRequest(
    fromSessionId: sessionId,
    toSessionId: toSessionId,
  );
  ConnectionHub.instance.pushEncounterSnapshot(sessionId);
  ConnectionHub.instance.pushEncounterSnapshot(toSessionId);
}

void _handleRespondToEncounterRequest(
  String sessionId,
  Map<String, dynamic> decoded,
) {
  final requestId = decoded['requestId'] as String?;
  final accepted = decoded['accepted'] as bool?;
  if (requestId == null || accepted == null) return;

  final ({EncounterRequest request, List<EncounterRequest> alsoCancelled})
  result;
  try {
    result = EncounterStore.instance.respondToRequest(
      requestId: requestId,
      accepted: accepted,
    );
  } on ArgumentError {
    return;
  }

  final touchedSessionIds = {
    result.request.fromSessionId,
    result.request.toSessionId,
    for (final cancelled in result.alsoCancelled) ...[
      cancelled.fromSessionId,
      cancelled.toSessionId,
    ],
  };
  for (final id in touchedSessionIds) {
    ConnectionHub.instance.pushEncounterSnapshot(id);
  }
}

void _handleChatMessage(String sessionId, Map<String, dynamic> decoded) {
  final toSessionId = decoded['toSessionId'] as String?;
  final text = decoded['text'] as String?;
  final sentAt = decoded['sentAt'] as String?;
  if (toSessionId == null || text == null || sentAt == null) return;

  ConnectionHub.instance.relayChatMessage(
    fromSessionId: sessionId,
    toSessionId: toSessionId,
    text: text,
    sentAt: sentAt,
  );
}

void _handleEndMatch(String sessionId, Map<String, dynamic> decoded) {
  final requestId = decoded['requestId'] as String?;
  if (requestId == null) return;

  final EncounterRequest request;
  try {
    request = EncounterStore.instance.endMatch(requestId);
  } on ArgumentError {
    return;
  }

  ConnectionHub.instance.pushEncounterSnapshot(request.fromSessionId);
  ConnectionHub.instance.pushEncounterSnapshot(request.toSessionId);
}
