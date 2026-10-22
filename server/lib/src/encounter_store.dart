import 'dart:math';

import 'package:threemojo_server/src/encounter_proposal.dart';

/// Ciclo di vita di una richiesta — stessi stadi del client Flutter
/// (`EncounterRequestStatus` in
/// `lib/features/encounters/domain/entities/encounter_request.dart`).
enum EncounterRequestStatus { pending, accepted, declined, cancelled, ended }

/// Stati finali: la richiesta non cambierà più. Negli snapshot verso il
/// client, per questi stati non si manda più né selfie né profilo
/// dell'altra persona (non serve più a nulla mostrarli).
const terminalEncounterStatuses = {
  EncounterRequestStatus.declined,
  EncounterRequestStatus.cancelled,
  EncounterRequestStatus.ended,
};

/// Perché il server ha rifiutato un'azione su una richiesta d'incontro —
/// mandato al client nel messaggio `rejected` (vedi `RealtimeMessageHandler`).
enum EncounterRejectionReason {
  /// Richiesta a se stessi.
  self,

  /// Il destinatario non è online/connesso ora.
  notOnline,

  /// Il destinatario non è (più) nella lista "Vicinanze" di chi chiede.
  notNearby,

  /// Il destinatario è dietro il paywall per chi chiede.
  locked,

  /// Esiste già una richiesta tra i due in questa sessione (in qualsiasi
  /// stato, anche rifiutata: niente rimandare).
  alreadyRequested,

  /// Una delle due parti è già in un match attivo.
  inMatch,

  /// Troppe richieste pendenti (in uscita per chi chiede, o in entrata per
  /// chi riceve).
  tooManyPending,
}

/// Una regola di business ha rifiutato l'azione. Estende `ArgumentError`
/// come gli altri rifiuti dello store, così chi chiama può gestirli insieme.
class EncounterRejected extends ArgumentError {
  EncounterRejected(this.reason) : super(reason.name);

  final EncounterRejectionReason reason;
}

/// Una richiesta d'interesse tra due sessioni, identificate dal loro id
/// interno — niente nomi, come tutto il resto dell'app.
class EncounterRequest {
  EncounterRequest({
    required this.id,
    required this.fromSessionId,
    required this.toSessionId,
    this.proposal = EncounterProposal.fallback,
    this.status = EncounterRequestStatus.pending,
  });

  final String id;
  final String fromSessionId;
  final String toSessionId;

  /// Cosa propone chi chiede (un codice di [EncounterProposal]), fissato
  /// all'invio: mostrato a entrambi i lati finché la richiesta esiste.
  final String proposal;
  EncounterRequestStatus status;

  bool involves(String sessionId) =>
      fromSessionId == sessionId || toSessionId == sessionId;

  /// L'altra sessione, dal punto di vista di `sessionId`.
  String otherSessionId(String sessionId) =>
      sessionId == fromSessionId ? toSessionId : fromSessionId;
}

/// Tiene in memoria le richieste d'interesse tra sessioni online — un
/// singleton in RAM, come `SessionStore`: nessuna persistenza, nessun
/// account, coerente con "usa e getta". Le richieste di una sessione (anche
/// quelle finite) restano finché la sessione vive — servono a impedire di
/// rimandare una richiesta alla stessa persona — e vengono tolte del tutto
/// quando finisce ([forgetSession]): niente cresce all'infinito.
class EncounterStore {
  EncounterStore._({Random? random}) : _random = random ?? Random.secure();

  /// Solo per i test: un'istanza vuota e indipendente, invece del singleton
  /// condiviso.
  factory EncounterStore.empty({Random? random}) =>
      EncounterStore._(random: random);

  static final EncounterStore instance = EncounterStore._();

  /// Richieste in uscita ancora in attesa per sessione: oltre, si aspetta
  /// una risposta prima di chiederne altre.
  static const maxPendingOutgoing = 5;

  /// Richieste in entrata ancora in attesa per sessione: un tetto contro chi
  /// (anche con più sessioni) inonderebbe qualcuno di richieste.
  static const maxPendingIncoming = 20;

  final Random _random;
  final Map<String, EncounterRequest> _requests = {};

  /// Crea una richiesta pendente. Le regole che dipendono solo dalle
  /// richieste stanno qui (lancia [EncounterRejected]): non a se stessi,
  /// nessuna richiesta già esistente per la coppia (in qualsiasi direzione e
  /// stato), nessuna delle due parti già in un match, tetti alle pendenti.
  /// Quelle che dipendono da chi è vicino a chi (online, in lista, paywall)
  /// le controlla chi chiama (`RealtimeMessageHandler`), che conosce
  /// `SessionStore`.
  ///
  /// [proposal] passa da [EncounterProposal.parse]: un codice fuori dalla
  /// lista chiusa diventa quello di ripiego, mai un valore arbitrario.
  EncounterRequest sendRequest({
    required String fromSessionId,
    required String toSessionId,
    String proposal = EncounterProposal.fallback,
  }) {
    if (fromSessionId == toSessionId) {
      throw EncounterRejected(EncounterRejectionReason.self);
    }
    if (_requests.values.any(
      (r) => r.involves(fromSessionId) && r.involves(toSessionId),
    )) {
      throw EncounterRejected(EncounterRejectionReason.alreadyRequested);
    }
    if (hasAnyActiveMatch(fromSessionId) || hasAnyActiveMatch(toSessionId)) {
      throw EncounterRejected(EncounterRejectionReason.inMatch);
    }
    final pendingOutgoing = _requests.values.where(
      (r) =>
          r.fromSessionId == fromSessionId &&
          r.status == EncounterRequestStatus.pending,
    );
    final pendingIncoming = _requests.values.where(
      (r) =>
          r.toSessionId == toSessionId &&
          r.status == EncounterRequestStatus.pending,
    );
    if (pendingOutgoing.length >= maxPendingOutgoing ||
        pendingIncoming.length >= maxPendingIncoming) {
      throw EncounterRejected(EncounterRejectionReason.tooManyPending);
    }

    var id = _newId();
    while (_requests.containsKey(id)) {
      id = _newId();
    }
    final request = EncounterRequest(
      id: id,
      fromSessionId: fromSessionId,
      toSessionId: toSessionId,
      proposal: EncounterProposal.parse(proposal),
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
  ///
  /// Solo il destinatario ([bySessionId] == `toSessionId`) può rispondere, e
  /// solo finché è pendente — senza questo controllo chiunque conoscesse un
  /// id potrebbe accettare o rifiutare le richieste degli altri. Accettare è
  /// rifiutato ([EncounterRejectionReason.inMatch]) se una delle due parti è
  /// già in un match.
  ({EncounterRequest request, List<EncounterRequest> alsoCancelled})
  respondToRequest({
    required String requestId,
    required bool accepted,
    required String bySessionId,
  }) {
    final request = _requests[requestId];
    if (request == null) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'Richiesta non trovata',
      );
    }
    if (request.toSessionId != bySessionId) {
      throw ArgumentError.value(
        bySessionId,
        'bySessionId',
        'Solo il destinatario può rispondere',
      );
    }
    if (request.status != EncounterRequestStatus.pending) {
      throw ArgumentError.value(requestId, 'requestId', 'Non più pendente');
    }
    if (accepted &&
        (hasAnyActiveMatch(request.fromSessionId) ||
            hasAnyActiveMatch(request.toSessionId))) {
      throw EncounterRejected(EncounterRejectionReason.inMatch);
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

  /// Chiude un match. Solo uno dei due partecipanti ([bySessionId]) può
  /// farlo, e solo su un match davvero attivo.
  EncounterRequest endMatch(String requestId, {required String bySessionId}) {
    final request = _requests[requestId];
    if (request == null) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'Richiesta non trovata',
      );
    }
    if (!request.involves(bySessionId)) {
      throw ArgumentError.value(
        bySessionId,
        'bySessionId',
        'Solo i partecipanti possono chiudere il match',
      );
    }
    if (request.status != EncounterRequestStatus.accepted) {
      throw ArgumentError.value(requestId, 'requestId', 'Nessun match attivo');
    }
    request.status = EncounterRequestStatus.ended;
    return request;
  }

  /// `true` se tra le due sessioni c'è un match attivo (richiesta accettata
  /// e non ancora chiusa) — l'unico caso in cui il server inoltra la chat.
  bool hasActiveMatch(String sessionIdA, String sessionIdB) =>
      _requests.values.any(
        (r) =>
            r.status == EncounterRequestStatus.accepted &&
            r.involves(sessionIdA) &&
            r.involves(sessionIdB),
      );

  /// `true` se [sessionId] è in un match attivo con chiunque.
  bool hasAnyActiveMatch(String sessionId) => _requests.values.any(
    (r) => r.status == EncounterRequestStatus.accepted && r.involves(sessionId),
  );

  /// Quando una sessione finisce, le sue richieste ancora pendenti non
  /// hanno più senso: chi le ha ricevute non potrebbe comunque mai ottenere
  /// risposta. Le cancella e ritorna quelle toccate, per notificare l'altra
  /// parte.
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

  /// Quando una sessione finisce, il suo match attivo (se c'è) finisce con
  /// lei: `accepted` → `ended`. Ritorna quelli toccati, per notificare il
  /// partner (che altrimenti resterebbe in una chat con nessuno).
  List<EncounterRequest> endActiveMatchesFor(String sessionId) {
    final affected = <EncounterRequest>[];
    for (final request in _requests.values) {
      if (request.status != EncounterRequestStatus.accepted) continue;
      if (!request.involves(sessionId)) continue;
      request.status = EncounterRequestStatus.ended;
      affected.add(request);
    }
    return affected;
  }

  /// Un blocco tra [sessionIdA] e [sessionIdB] (vedi `BlockStore`): tra i
  /// due le richieste pendenti diventano `cancelled` e il match attivo
  /// `ended` — **gli stessi passaggi** di [cancelAllPendingFor] e
  /// [endActiveMatchesFor] quando una sessione finisce, così chi è bloccato
  /// vede ciò che vedrebbe se l'altro avesse premuto End. Ritorna quelle
  /// toccate, per notificare.
  List<EncounterRequest> closeAllBetween(String sessionIdA, String sessionIdB) {
    final affected = <EncounterRequest>[];
    for (final request in _requests.values) {
      if (!request.involves(sessionIdA) || !request.involves(sessionIdB)) {
        continue;
      }
      switch (request.status) {
        case EncounterRequestStatus.pending:
          request.status = EncounterRequestStatus.cancelled;
          affected.add(request);
        case EncounterRequestStatus.accepted:
          request.status = EncounterRequestStatus.ended;
          affected.add(request);
        case EncounterRequestStatus.declined ||
            EncounterRequestStatus.cancelled ||
            EncounterRequestStatus.ended:
          break;
      }
    }
    return affected;
  }

  /// Toglie ogni richiesta tra [sessionIdA] e [sessionIdB] — dopo un blocco
  /// e dopo averli notificati, come [forgetSession] a fine sessione.
  void forgetPair(String sessionIdA, String sessionIdB) =>
      _requests.removeWhere(
        (_, request) =>
            request.involves(sessionIdA) && request.involves(sessionIdB),
      );

  /// Toglie del tutto ogni richiesta che coinvolge [sessionId] — l'ultimo
  /// passo della fine sessione, dopo aver notificato le controparti.
  void forgetSession(String sessionId) =>
      _requests.removeWhere((_, request) => request.involves(sessionId));

  /// Quante richieste sono in memoria — solo per test e diagnostica.
  int get length => _requests.length;

  /// Id casuali, non sequenziali: un contatore direbbe a chiunque quante
  /// richieste sono state fatte, e renderebbe gli id indovinabili.
  String _newId() {
    final buffer = StringBuffer('req-');
    for (var i = 0; i < 12; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
