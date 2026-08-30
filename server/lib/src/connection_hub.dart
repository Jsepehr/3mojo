import 'dart:async';
import 'dart:convert';

import 'package:threemojo_server/src/encounter_store.dart';
import 'package:threemojo_server/src/session_store.dart';

/// Tiene i canali WebSocket dei client online e spinge a ognuno gli
/// aggiornamenti che lo riguardano — "vicinanze" e richieste d'incontro —
/// sostituendo il polling HTTP con un push quasi istantaneo. Non tiene lo
/// stream in ingresso (quello lo legge direttamente la route `/ws`, che sa
/// interpretare i messaggi): solo il lato di scrittura, cosicché resti
/// testabile senza un vero `WebSocketChannel`.
class ConnectionHub {
  ConnectionHub._(this._sessionStore, this._encounterStore);

  /// Solo per i test: un hub agganciato a store controllabili invece dei
  /// singleton condivisi.
  factory ConnectionHub.withStore(
    SessionStore sessionStore, {
    EncounterStore? encounterStore,
  }) => ConnectionHub._(sessionStore, encounterStore ?? EncounterStore.instance);

  static final ConnectionHub instance = ConnectionHub._(
    SessionStore.instance,
    EncounterStore.instance,
  );

  static const double radiusMeters = 150;

  final SessionStore _sessionStore;
  final EncounterStore _encounterStore;
  final Map<String, StreamSink<dynamic>> _sinks = {};

  void register(String sessionId, StreamSink<dynamic> sink) {
    _sinks[sessionId] = sink;
  }

  void unregister(String sessionId) {
    _sinks.remove(sessionId);
  }

  void _sendTo(String sessionId, Map<String, dynamic> message) {
    _sinks[sessionId]?.add(jsonEncode(message));
  }

  /// Inoltra un messaggio di chat a `toSessionId`, se connesso in questo
  /// momento — il server fa solo da postino, non lo conserva da nessuna
  /// parte: se il destinatario non è online, il messaggio va perso (chi
  /// l'ha mandato lo tiene comunque nella propria cronologia locale).
  void relayChatMessage({
    required String fromSessionId,
    required String toSessionId,
    required String text,
    required String sentAt,
  }) {
    _sendTo(toSessionId, {
      'type': 'chatMessage',
      'fromSessionId': fromSessionId,
      'text': text,
      'sentAt': sentAt,
    });
  }

  /// Ricalcola e manda a ognuno dei client connessi la sua lista
  /// "vicinanze" aggiornata (ognuno riceve la propria, già filtrata per
  /// genere/raggio/permanenza da `SessionStore.nearbyPeople`).
  void broadcastNearbyUpdates() {
    for (final sessionId in _sinks.keys) {
      final people = _sessionStore.nearbyPeople(
        sessionId: sessionId,
        radiusMeters: radiusMeters,
      );
      if (people == null) continue;

      _sendTo(sessionId, {
        'type': 'nearby',
        'people': people.map((p) => p.toJson()).toList(),
      });
    }
  }

  /// Manda a `sessionId` (se connesso) le sue richieste in entrata/uscita
  /// aggiornate, con selfie della controparte preso da `SessionStore` —
  /// niente da conservare nella richiesta stessa, sempre fresco.
  void pushEncounterSnapshot(String sessionId) {
    if (!_sinks.containsKey(sessionId)) return;

    Map<String, dynamic> toJson(EncounterRequest r) {
      final other = _sessionStore.selfieBase64For(r.otherSessionId(sessionId));
      return {
        'id': r.id,
        'otherSessionId': r.otherSessionId(sessionId),
        'otherSelfieBase64': other ?? '',
        'status': r.status.name,
      };
    }

    _sendTo(sessionId, {
      'type': 'encounters',
      'incoming': _encounterStore.incomingFor(sessionId).map(toJson).toList(),
      'outgoing': _encounterStore.outgoingFor(sessionId).map(toJson).toList(),
    });
  }
}
