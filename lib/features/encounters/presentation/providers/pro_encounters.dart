import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/profile/domain/entities/profile.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/watch_server_session_restarts_usecase.dart';
import '/features/session/domain/usecases/watch_session_usecase.dart';
import '../../domain/entities/encounter_proposal.dart';
import '../../domain/entities/encounter_rejection.dart';
import '../../domain/entities/encounter_request.dart';
import '../../domain/entities/match_end.dart';
import '../../domain/usecases/detect_ended_match_usecase.dart';
import '../../domain/usecases/end_match_usecase.dart';
import '../../domain/usecases/find_active_match_usecase.dart';
import '../../domain/usecases/find_lost_encounter_requests_usecase.dart';
import '../../domain/usecases/has_requested_person_usecase.dart';
import '../../domain/usecases/preselect_encounter_proposal_usecase.dart';
import '../../domain/usecases/proposal_for_intent_usecase.dart';
import '../../domain/usecases/respond_to_encounter_request_usecase.dart';
import '../../domain/usecases/send_encounter_request_usecase.dart';
import '../../domain/usecases/watch_encounter_rejections_usecase.dart';
import '../../domain/usecases/watch_encounter_requests_usecase.dart';
import '../encounter_notice.dart';

/// Stato di richieste in entrata/uscita — spinte dal server sulla
/// connessione condivisa con `nearby`. `activeMatch` espone la richiesta
/// accettata — usata da `CmpMatchGate` per aprire (e chiudere) la pagina
/// del match a schermo intero.
///
/// **Lavora solo da online**, guidato dal ciclo di vita della sessione
/// (`WatchSessionUseCase`): a ogni Start si abbona, a End (o senza
/// sessione, `NotOnlineFailure`) si ferma e svuota tutto — niente badge né
/// richieste della sessione precedente. Le cadute di rete non toccano le
/// liste (la riconnessione è automatica); se però il server ha dimenticato
/// la sessione durante la caduta (`WatchServerSessionRestartsUseCase`) le
/// liste si azzerano e l'eventuale chat del match se ne va con loro.
///
/// "Chi ho già richiesto" non è più uno stato a parte: si deriva dallo
/// snapshot del server ([hasRequested]), più le richieste appena partite
/// che lo snapshot non mostra ancora. Quelle mai confermate entro il tempo
/// della regola (`FindLostEncounterRequestsUseCase`) si considerano perse:
/// tornano richiedibili e l'utente lo sa (`RequestNotConfirmedFailure`).
///
/// Le regole non stanno qui: "qual è il match attivo"
/// (`FindActiveMatchUseCase`), "è finito dall'altra parte?" e la
/// cancellazione della sua chat (`DetectEndedMatchUseCase`), "quando una
/// richiesta è persa" (`FindLostEncounterRequestsUseCase`). Il provider
/// tiene lo stato e le traduce in [EncounterNotice].
///
/// Tiene anche l'**ultima proposta scelta** in questa sessione (solo in
/// memoria, dimenticata a End come il resto): con l'intento di sessione è
/// ciò da cui `PreselectEncounterProposalUseCase` decide la proposta già
/// scelta nella tendina ([preselectedProposal]).
class ProEncounters extends ChangeNotifier {
  ProEncounters({
    required WatchSessionUseCase watchSessionUseCase,
    required WatchServerSessionRestartsUseCase
    watchServerSessionRestartsUseCase,
    required WatchEncounterRequestsUseCase watchEncounterRequestsUseCase,
    required WatchEncounterRejectionsUseCase watchEncounterRejectionsUseCase,
    required SendEncounterRequestUseCase sendEncounterRequestUseCase,
    required RespondToEncounterRequestUseCase respondToEncounterRequestUseCase,
    required EndMatchUseCase endMatchUseCase,
    required DetectEndedMatchUseCase detectEndedMatchUseCase,
    HasRequestedPersonUseCase hasRequestedPersonUseCase =
        const HasRequestedPersonUseCase(),
    FindActiveMatchUseCase findActiveMatchUseCase =
        const FindActiveMatchUseCase(),
    FindLostEncounterRequestsUseCase findLostEncounterRequestsUseCase =
        const FindLostEncounterRequestsUseCase(),
    PreselectEncounterProposalUseCase preselectEncounterProposalUseCase =
        const PreselectEncounterProposalUseCase(),
    ProposalForIntentUseCase proposalForIntentUseCase =
        const ProposalForIntentUseCase(),
    DateTime Function()? now,
  }) : _watchEncounterRequestsUseCase = watchEncounterRequestsUseCase,
       _watchEncounterRejectionsUseCase = watchEncounterRejectionsUseCase,
       _sendEncounterRequestUseCase = sendEncounterRequestUseCase,
       _respondToEncounterRequestUseCase = respondToEncounterRequestUseCase,
       _endMatchUseCase = endMatchUseCase,
       _detectEndedMatchUseCase = detectEndedMatchUseCase,
       _hasRequestedPersonUseCase = hasRequestedPersonUseCase,
       _findActiveMatchUseCase = findActiveMatchUseCase,
       _findLostEncounterRequestsUseCase = findLostEncounterRequestsUseCase,
       _preselectEncounterProposalUseCase = preselectEncounterProposalUseCase,
       _proposalForIntentUseCase = proposalForIntentUseCase,
       _now = now ?? DateTime.now {
    _sessionSubscription = watchSessionUseCase().listen(_onSession);
    _restartSubscription = watchServerSessionRestartsUseCase().listen(
      (_) => _onServerSessionRestarted(),
    );
  }

  final WatchEncounterRequestsUseCase _watchEncounterRequestsUseCase;
  final WatchEncounterRejectionsUseCase _watchEncounterRejectionsUseCase;
  final SendEncounterRequestUseCase _sendEncounterRequestUseCase;
  final RespondToEncounterRequestUseCase _respondToEncounterRequestUseCase;
  final EndMatchUseCase _endMatchUseCase;
  final DetectEndedMatchUseCase _detectEndedMatchUseCase;
  final HasRequestedPersonUseCase _hasRequestedPersonUseCase;
  final FindActiveMatchUseCase _findActiveMatchUseCase;
  final FindLostEncounterRequestsUseCase _findLostEncounterRequestsUseCase;
  final PreselectEncounterProposalUseCase _preselectEncounterProposalUseCase;
  final ProposalForIntentUseCase _proposalForIntentUseCase;
  final DateTime Function() _now;
  Timer? _lostRequestsTimer;

  late final StreamSubscription<OnlineSession?> _sessionSubscription;
  late final StreamSubscription<void> _restartSubscription;
  StreamSubscription<void>? _requestsSubscription;
  StreamSubscription<void>? _rejectionsSubscription;
  final StreamController<EncounterNotice> _notices =
      StreamController.broadcast();

  String? _sessionId;

  /// L'intento della sessione in corso e l'ultima proposta mandata in
  /// questa sessione: solo in memoria, azzerati a ogni Start/End.
  MeetIntent? _ownIntent;
  EncounterProposal? _lastProposal;

  List<EncounterRequest> _incomingRequests = [];
  List<EncounterRequest> _outgoingRequests = [];

  /// Persone a cui una richiesta è partita (con l'ora di partenza) ma che
  /// lo snapshot non mostra ancora: la loro tile è già "richiesta" (niente
  /// doppio tap), finché non è confermata, rifiutata o considerata persa.
  final Map<String, DateTime> _awaitingSentAt = {};

  Set<String> get _awaitingPersonIds => _awaitingSentAt.keys.toSet();

  /// Match chiusi da te: uno snapshot ancora in volo che li mostra
  /// accettati non deve riaprire la pagina del match.
  final Set<String> _locallyEndedIds = {};

  /// Match che stai chiudendo proprio ora: se nel frattempo arriva lo
  /// snapshot che li mostra finiti, non è "l'altra persona è uscita".
  final Set<String> _endingIds = {};

  List<EncounterRequest> get incomingRequests => _incomingRequests;
  List<EncounterRequest> get outgoingRequests => _outgoingRequests;

  /// Eventi una tantum da mostrare all'utente.
  Stream<EncounterNotice> get notices => _notices.stream;

  int get pendingIncomingCount => _incomingRequests
      .where((r) => r.status == EncounterRequestStatus.pending)
      .length;

  EncounterRequest? get activeMatch => _findActiveMatchUseCase([
    ..._incomingRequests,
    ..._outgoingRequests,
  ], locallyEndedIds: _locallyEndedIds);

  /// C'è già una richiesta con questa persona (o sta partendo)? Per la UI di
  /// "Vicinanze": la stessa regola di `SendEncounterRequestUseCase`.
  bool hasRequested(String otherPersonId) => _hasRequestedPersonUseCase(
    otherPersonId,
    requests: [..._incomingRequests, ..._outgoingRequests],
    awaitingPersonIds: _awaitingPersonIds,
  );

  /// La proposta già scelta (e in cima) aprendo la tendina: l'ultima
  /// mandata in questa sessione, altrimenti quella del tuo intento.
  EncounterProposal get preselectedProposal =>
      _preselectEncounterProposalUseCase(
        lastChosen: _lastProposal,
        ownIntent: _ownIntent,
      );

  /// La proposta "in linea con ciò che cerca" chi mostra [intent] in
  /// "Vicinanze" (il suo intento pubblico), o `null` se non ne mostra uno.
  EncounterProposal? proposalMatchingIntent(MeetIntent? intent) =>
      intent == null ? null : _proposalForIntentUseCase(intent);

  void sendRequest(
    String otherPersonId, {
    EncounterProposal proposal = EncounterProposal.fallback,
  }) {
    final result = _sendEncounterRequestUseCase(
      SendEncounterRequestParams(
        otherPersonId: otherPersonId,
        proposal: proposal,
        knownRequests: [..._incomingRequests, ..._outgoingRequests],
        awaitingPersonIds: _awaitingPersonIds,
      ),
    );
    result.match(
      (failure) => _notices.add(
        ActionNotSentNotice(EncounterAction.sendRequest, failure),
      ),
      (_) {
        _lastProposal = proposal;
        _awaitingSentAt[otherPersonId] = _now();
        _scheduleLostRequestsCheck();
      },
    );
    notifyListeners();
  }

  /// Controlla, allo scadere del tempo della regola per la più vecchia, se
  /// qualche richiesta in attesa va considerata persa.
  void _scheduleLostRequestsCheck() {
    if (_lostRequestsTimer != null || _awaitingSentAt.isEmpty) return;
    final oldest = _awaitingSentAt.values.reduce(
      (a, b) => a.isBefore(b) ? a : b,
    );
    var wait =
        FindLostEncounterRequestsUseCase.confirmationTimeout -
        _now().difference(oldest);
    if (wait.isNegative) wait = Duration.zero;
    _lostRequestsTimer = Timer(wait, _expireLostRequests);
  }

  void _expireLostRequests() {
    _lostRequestsTimer = null;
    final lost = _findLostEncounterRequestsUseCase(
      _awaitingSentAt,
      now: _now(),
    );
    for (final personId in lost) {
      _awaitingSentAt.remove(personId);
      _notices.add(
        const ActionNotSentNotice(
          EncounterAction.sendRequest,
          RequestNotConfirmedFailure(),
        ),
      );
    }
    _scheduleLostRequestsCheck();
    if (lost.isNotEmpty) notifyListeners();
  }

  void respondToRequest(String requestId, bool accepted) {
    final result = _respondToEncounterRequestUseCase(
      RespondToEncounterRequestParams(requestId: requestId, accepted: accepted),
    );
    result.match(
      (failure) => _notices.add(
        ActionNotSentNotice(EncounterAction.respondToRequest, failure),
      ),
      (_) {},
    );
  }

  /// Chiude il match. Solo se è partito verso il server lo si considera
  /// chiuso anche qui (e la pagina del match si chiude); altrimenti la
  /// pagina resta e chi chiama mostra l'errore.
  Future<Either<Failure, Unit>> endMatch({
    required String requestId,
    required String otherPersonId,
  }) async {
    _endingIds.add(requestId);
    final result = await _endMatchUseCase(
      requestId: requestId,
      otherPersonId: otherPersonId,
    );
    _endingIds.remove(requestId);
    if (result.isRight()) {
      _locallyEndedIds.add(requestId);
      notifyListeners();
    }
    return result;
  }

  void _onSession(OnlineSession? session) {
    final sessionId = session?.sessionId;
    if (sessionId == _sessionId) return;

    _requestsSubscription?.cancel();
    _requestsSubscription = null;
    _rejectionsSubscription?.cancel();
    _rejectionsSubscription = null;
    _clearState();
    _sessionId = sessionId;
    // Sessione nuova (o nessuna): la proposta di quella prima non vale più.
    _ownIntent = session?.intent;
    _lastProposal = null;
    if (sessionId != null) _subscribe();
    notifyListeners();
  }

  void _subscribe() {
    _requestsSubscription = _watchEncounterRequestsUseCase().listen(
      _onSnapshot,
    );
    _rejectionsSubscription = _watchEncounterRejectionsUseCase().listen(
      _onRejection,
    );
  }

  void _onSnapshot(
    Either<
      Failure,
      ({List<EncounterRequest> incoming, List<EncounterRequest> outgoing})
    >
    result,
  ) {
    switch (result) {
      case Left(value: NotOnlineFailure()):
        // Nessuna sessione: le richieste di prima non valgono più.
        _clearState();
      case Left():
        // Caduta di rete o simili: si tiene ciò che si sa, la
        // riconnessione è automatica (vedi `CmpConnectionBanner`).
        return;
      case Right(value: final snapshot):
        final previous = [..._incomingRequests, ..._outgoingRequests];
        _incomingRequests = snapshot.incoming;
        _outgoingRequests = snapshot.outgoing;
        _confirmAwaitingRequests();
        unawaited(
          _reportEndedMatch(
            _detectEndedMatchUseCase(
              previous: previous,
              next: [...snapshot.incoming, ...snapshot.outgoing],
              locallyEndedIds: Set.of(_locallyEndedIds),
              endingIds: Set.of(_endingIds),
            ),
          ),
        );
    }
    notifyListeners();
  }

  void _confirmAwaitingRequests() {
    final confirmed = _awaitingSentAt.keys
        .where((id) => _outgoingRequests.any((r) => r.otherPersonId == id))
        .toList();
    for (final id in confirmed) {
      _awaitingSentAt.remove(id);
      _notices.add(const RequestSentNotice());
    }
  }

  /// L'avviso "l'altra persona è uscita" solo per un match finito
  /// dall'altra parte: il riavvio della sessione sul server lo racconta
  /// già `CmpConnectionNoticeListener`.
  Future<void> _reportEndedMatch(Future<MatchEnd?> detection) async {
    final ended = await detection;
    if (ended?.reason == MatchEndReason.endedByPartner && !_notices.isClosed) {
      _notices.add(const MatchEndedByPartnerNotice());
    }
  }

  void _onRejection(EncounterRejection rejection) {
    final otherPersonId = rejection.otherPersonId;
    if (rejection.action == EncounterAction.sendRequest &&
        otherPersonId != null) {
      _awaitingSentAt.remove(otherPersonId);
    }
    _notices.add(ActionRejectedNotice(rejection));
    notifyListeners();
  }

  /// Il server ha dimenticato la sessione durante una caduta: richieste e
  /// match di prima non esistono più lì. L'avviso lo mostra
  /// `CmpConnectionNoticeListener`; qui si azzera lo stato locale (e la
  /// chat dell'eventuale match).
  void _onServerSessionRestarted() {
    if (_sessionId == null) return;
    unawaited(
      _detectEndedMatchUseCase(
        previous: [..._incomingRequests, ..._outgoingRequests],
        next: const [],
        locallyEndedIds: Set.of(_locallyEndedIds),
        sessionRestarted: true,
      ),
    );
    _clearState();
    notifyListeners();
  }

  void _clearState() {
    _incomingRequests = [];
    _outgoingRequests = [];
    _awaitingSentAt.clear();
    _lostRequestsTimer?.cancel();
    _lostRequestsTimer = null;
    _locallyEndedIds.clear();
    _endingIds.clear();
  }

  @override
  void dispose() {
    _sessionSubscription.cancel();
    _restartSubscription.cancel();
    _requestsSubscription?.cancel();
    _rejectionsSubscription?.cancel();
    _lostRequestsTimer?.cancel();
    _notices.close();
    super.dispose();
  }
}
