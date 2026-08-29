/// Ciclo di vita di una richiesta — stessi stadi del client Flutter
/// (`EncounterRequestStatus` in
/// `lib/features/encounters/domain/entities/encounter_request.dart`).
enum EncounterRequestStatus { pending, accepted, declined, cancelled, ended }

/// Una richiesta d'interesse tra due sessioni, identificate dal loro
/// `sessionId` — niente nomi, come tutto il resto dell'app.
class EncounterRequest {
  EncounterRequest({
    required this.id,
    required this.fromSessionId,
    required this.toSessionId,
    this.status = EncounterRequestStatus.pending,
  });

  final String id;
  final String fromSessionId;
  final String toSessionId;
  EncounterRequestStatus status;

  bool involves(String sessionId) =>
      fromSessionId == sessionId || toSessionId == sessionId;

  /// L'altra sessione, dal punto di vista di `sessionId`.
  String otherSessionId(String sessionId) =>
      sessionId == fromSessionId ? toSessionId : fromSessionId;
}

/// Tiene in memoria le richieste d'interesse tra sessioni online — un
/// singleton in RAM, come `SessionStore`: nessuna persistenza, nessun
/// account, coerente con "usa e getta".
class EncounterStore {
  EncounterStore._();

  /// Solo per i test: un'istanza vuota e indipendente, invece del singleton
  /// condiviso.
  factory EncounterStore.empty() => EncounterStore._();

  static final EncounterStore instance = EncounterStore._();

  final Map<String, EncounterRequest> _requests = {};
  int _counter = 0;

  EncounterRequest sendRequest({
    required String fromSessionId,
    required String toSessionId,
  }) {
    _counter++;
    final request = EncounterRequest(
      id: 'req-$_counter',
      fromSessionId: fromSessionId,
      toSessionId: toSessionId,
    );
    _requests[request.id] = request;
    return request;
  }

  List<EncounterRequest> incomingFor(String sessionId) => _requests.values
      .where((r) => r.toSessionId == sessionId)
      .toList(growable: false);

  List<EncounterRequest> outgoingFor(String sessionId) => _requests.values
      .where((r) => r.fromSessionId == sessionId)
      .toList(growable: false);

  /// Risponde a una richiesta. Se accettata, applica da sola la regola di
  /// esclusività — "un solo incontro attivo alla volta" per **entrambi** i
  /// partecipanti — cancellando ogni altra richiesta pendente che coinvolga
  /// l'uno o l'altro. Ritorna la richiesta aggiornata più quelle cancellate
  /// come effetto collaterale, così chi chiama sa a chi altro notificare.
  ({EncounterRequest request, List<EncounterRequest> alsoCancelled})
  respondToRequest({required String requestId, required bool accepted}) {
    final request = _requests[requestId];
    if (request == null) {
      throw ArgumentError.value(requestId, 'requestId', 'Richiesta non trovata');
    }

    request.status = accepted
        ? EncounterRequestStatus.accepted
        : EncounterRequestStatus.declined;

    final alsoCancelled = <EncounterRequest>[];
    if (accepted) {
      for (final other in _requests.values) {
        if (other.id == request.id) continue;
        if (other.status != EncounterRequestStatus.pending) continue;
        if (!other.involves(request.fromSessionId) &&
            !other.involves(request.toSessionId)) {
          continue;
        }
        other.status = EncounterRequestStatus.cancelled;
        alsoCancelled.add(other);
      }
    }

    return (request: request, alsoCancelled: alsoCancelled);
  }

  EncounterRequest endMatch(String requestId) {
    final request = _requests[requestId];
    if (request == null) {
      throw ArgumentError.value(requestId, 'requestId', 'Richiesta non trovata');
    }
    request.status = EncounterRequestStatus.ended;
    return request;
  }

  /// Quando una sessione sparisce (fine socket), le sue richieste ancora
  /// pendenti non hanno più senso: chi le ha ricevute non potrebbe comunque
  /// mai ottenere risposta. Le cancella e ritorna quelle toccate, per
  /// notificare l'altra parte.
  List<EncounterRequest> cancelAllPendingFor(String sessionId) {
    final affected = <EncounterRequest>[];
    for (final request in _requests.values) {
      if (request.status != EncounterRequestStatus.pending) continue;
      if (!request.involves(sessionId)) continue;
      request.status = EncounterRequestStatus.cancelled;
      affected.add(request);
    }
    return affected;
  }
}
