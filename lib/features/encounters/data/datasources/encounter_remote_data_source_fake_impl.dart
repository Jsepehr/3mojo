import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '/features/profile/domain/entities/profile.dart';
import '../../domain/entities/encounter_proposal.dart';
import '../../domain/entities/encounter_rejection.dart';
import '../../domain/entities/encounter_request.dart';
import '../models/encounter_rejection_model.dart';
import '../models/encounter_request_model.dart';
import 'encounter_remote_data_source.dart';

/// Implementazione **finta** (nessuna rete, nessun backend): tiene in
/// memoria le richieste in entrata/uscita, ogni tanto fa arrivare una
/// richiesta finta in entrata, e simula una risposta dopo qualche secondo a
/// quelle in uscita — applicando da sola le stesse regole del server vero:
/// "un solo incontro alla volta" quando è "l'altro" ad accettare, niente
/// seconda richiesta alla stessa persona, niente richieste a match in corso.
/// Le richieste in uscita conservano la proposta scelta; quelle finte in
/// entrata ne hanno una a caso dalla lista chiusa.
///
/// Lo stato è **per sessione**, come sul server: con una sessione nuova (un
/// `watchRequests` con un altro id) o con [reset] (End) si azzera tutto —
/// richieste, timer, stream — invece di riportare le richieste di ieri in
/// una sessione nuova.
///
/// Lo usa anche la **demo dichiarata** (`DemoScope`), in ogni build, con un
/// copione più prevedibile: le richieste in entrata arrivano da
/// [incomingRequesters] (persone della lista "Vicinanze" finta, con la
/// loro foto illustrata), ogni [incomingTickInterval], sempre
/// ([newIncomingProbability] 1), e le risposte alle tue richieste sono
/// sempre un sì ([acceptProbability] 1) dopo [responseDelay]. Le regole
/// (un incontro alla volta, una richiesta per coppia) restano le stesse.
class EncounterRemoteDataSourceFakeImpl implements EncounterRemoteDataSource {
  EncounterRemoteDataSourceFakeImpl({
    this.incomingTickInterval = const Duration(seconds: 5),
    this.responseDelay = const Duration(seconds: 4),
    this.newIncomingProbability = 0.3,
    this.acceptProbability = 0.6,
    this.incomingRequesters,
    this.selfieOf,
  });

  /// Ogni quanto può arrivare una richiesta finta in entrata.
  final Duration incomingTickInterval;

  /// Dopo quanto arriva la risposta finta a una tua richiesta.
  final Duration responseDelay;

  /// Probabilità che a ogni giro arrivi una richiesta in entrata (se non ce
  /// n'è già una in attesa e non c'è un match).
  final double newIncomingProbability;

  /// Probabilità che una tua richiesta venga accettata.
  final double acceptProbability;

  /// Chi manda le richieste in entrata, nell'ordine: ognuno una volta sola
  /// e solo se con lui non c'è già una richiesta. `null` = persone finte
  /// fuori dalla lista (`fake-person-N`), senza foto e con una proposta a
  /// caso.
  final List<FakeIncomingRequester>? incomingRequesters;

  /// La foto (illustrata) della persona [personId] da mettere sulle tue
  /// richieste, come fa il server per quelle in attesa o accettate (è
  /// quella che si vede nella pagina del match). `null` = nessuna foto.
  final Uint8List? Function(String personId)? selfieOf;

  final Random _random = Random();
  final List<EncounterRequestModel> _incoming = [];
  final List<EncounterRequestModel> _outgoing = [];
  StreamController<EncounterSnapshotModel>? _controller;
  final StreamController<EncounterRejectionModel> _rejections =
      StreamController.broadcast();
  Timer? _incomingTimer;
  final Set<Timer> _responseTimers = {};
  String? _sessionId;
  int _fakeIncomingCounter = 0;

  bool get _hasActiveMatch =>
      _incoming.any((r) => r.status == EncounterRequestStatus.accepted) ||
      _outgoing.any((r) => r.status == EncounterRequestStatus.accepted);

  @override
  Stream<EncounterSnapshotModel> watchRequests(String sessionId) {
    final existing = _controller;
    if (_sessionId == sessionId && existing != null && !existing.isClosed) {
      scheduleMicrotask(_emit);
      return existing.stream;
    }

    _clearState();
    unawaited(existing?.close());
    _sessionId = sessionId;
    final controller = StreamController<EncounterSnapshotModel>.broadcast();
    _controller = controller;
    _incomingTimer = Timer.periodic(
      incomingTickInterval,
      (_) => _maybeAddIncoming(),
    );
    scheduleMicrotask(_emit);
    return controller.stream;
  }

  @override
  Stream<EncounterRejectionModel> watchRejections(String sessionId) =>
      _rejections.stream;

  void _reject(
    EncounterAction action,
    EncounterRejectionReason reason, {
    String? otherPersonId,
    String? requestId,
  }) {
    _rejections.add(
      EncounterRejectionModel(
        action: action,
        reason: reason,
        otherPersonId: otherPersonId,
        requestId: requestId,
      ),
    );
  }

  @override
  Future<void> reset() async {
    _clearState();
    _sessionId = null;
    final controller = _controller;
    _controller = null;
    await controller?.close();
  }

  void _clearState() {
    _incomingTimer?.cancel();
    _incomingTimer = null;
    for (final timer in _responseTimers) {
      timer.cancel();
    }
    _responseTimers.clear();
    _incoming.clear();
    _outgoing.clear();
  }

  @override
  void sendRequest({
    required String otherPersonId,
    required EncounterProposal proposal,
  }) {
    final alreadyAsked = [
      ..._incoming,
      ..._outgoing,
    ].any((r) => r.otherPersonId == otherPersonId);
    if (alreadyAsked || _hasActiveMatch) {
      _reject(
        EncounterAction.sendRequest,
        alreadyAsked
            ? EncounterRejectionReason.alreadyRequested
            : EncounterRejectionReason.inMatch,
        otherPersonId: otherPersonId,
      );
      return;
    }

    final request = EncounterRequestModel(
      id: 'out-${DateTime.now().microsecondsSinceEpoch}',
      otherPersonId: otherPersonId,
      status: EncounterRequestStatus.pending,
      proposal: proposal,
      otherSelfieBytes: selfieOf?.call(otherPersonId),
    );
    _outgoing.add(request);
    _emit();

    late final Timer timer;
    timer = Timer(responseDelay, () {
      _responseTimers.remove(timer);
      final index = _outgoing.indexWhere((r) => r.id == request.id);
      if (index == -1 ||
          _outgoing[index].status != EncounterRequestStatus.pending) {
        return;
      }
      final accepted =
          !_hasActiveMatch && _random.nextDouble() < acceptProbability;
      _outgoing[index] = _outgoing[index].withStatus(
        accepted
            ? EncounterRequestStatus.accepted
            : EncounterRequestStatus.declined,
      );
      if (accepted) _cancelOtherPending(exceptId: request.id);
      _emit();
    });
    _responseTimers.add(timer);
  }

  @override
  void respondToRequest({required String requestId, required bool accepted}) {
    final index = _incoming.indexWhere((r) => r.id == requestId);
    if (index == -1 ||
        _incoming[index].status != EncounterRequestStatus.pending) {
      return;
    }
    if (accepted && _hasActiveMatch) {
      _reject(
        EncounterAction.respondToRequest,
        EncounterRejectionReason.inMatch,
        requestId: requestId,
      );
      return;
    }

    _incoming[index] = _incoming[index].withStatus(
      accepted
          ? EncounterRequestStatus.accepted
          : EncounterRequestStatus.declined,
    );
    if (accepted) _cancelOtherPending(exceptId: requestId);
    _emit();
  }

  @override
  void endMatch(String requestId) {
    for (final list in [_incoming, _outgoing]) {
      final index = list.indexWhere(
        (r) => r.id == requestId && r.status == EncounterRequestStatus.accepted,
      );
      if (index != -1) {
        list[index] = list[index].withStatus(EncounterRequestStatus.ended);
        _emit();
        return;
      }
    }
  }

  void _maybeAddIncoming() {
    final hasPending = _incoming.any(
      (r) => r.status == EncounterRequestStatus.pending,
    );
    if (hasPending || _hasActiveMatch) return;
    if (_random.nextDouble() >= newIncomingProbability) return;

    final requesters = incomingRequesters;
    if (requesters != null) {
      _addIncomingFrom(requesters);
      return;
    }

    _fakeIncomingCounter++;
    _incoming.add(
      EncounterRequestModel(
        id: 'in-$_fakeIncomingCounter-${DateTime.now().microsecondsSinceEpoch}',
        otherPersonId: 'fake-person-$_fakeIncomingCounter',
        status: EncounterRequestStatus.pending,
        proposal: EncounterProposal
            .values[_random.nextInt(EncounterProposal.values.length)],
        otherIntent:
            MeetIntent.values[_fakeIncomingCounter % MeetIntent.values.length],
        otherLanguages: _fakeIncomingCounter.isEven
            ? const ['it', 'en']
            : const ['it'],
        otherVisibleGender: _fakeIncomingCounter.isEven ? Gender.female : null,
      ),
    );
    _emit();
  }

  /// La prossima richiesta del copione: dal primo di [requesters] con cui
  /// non c'è ancora nessuna richiesta (in nessuno dei due versi). Finiti
  /// loro, non ne arrivano più.
  void _addIncomingFrom(List<FakeIncomingRequester> requesters) {
    final involved = {
      for (final request in [..._incoming, ..._outgoing]) request.otherPersonId,
    };
    final requester = requesters
        .where((candidate) => !involved.contains(candidate.personId))
        .firstOrNull;
    if (requester == null) return;

    _fakeIncomingCounter++;
    _incoming.add(
      EncounterRequestModel(
        id: 'in-$_fakeIncomingCounter-${DateTime.now().microsecondsSinceEpoch}',
        otherPersonId: requester.personId,
        status: EncounterRequestStatus.pending,
        proposal: requester.proposal,
        otherSelfieBytes: requester.selfieBytes,
        otherIntent: requester.intent,
        otherLanguages: requester.languages,
        otherVisibleGender: requester.visibleGender,
      ),
    );
    _emit();
  }

  void _cancelOtherPending({required String exceptId}) {
    for (final list in [_incoming, _outgoing]) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id != exceptId &&
            list[i].status == EncounterRequestStatus.pending) {
          list[i] = list[i].withStatus(EncounterRequestStatus.cancelled);
        }
      }
    }
  }

  void _emit() {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.add((
      incoming: List.unmodifiable(_incoming),
      outgoing: List.unmodifiable(_outgoing),
    ));
  }
}

/// Una persona che, nel copione della demo, ti manda una richiesta: lo
/// stesso pseudonimo e la stessa foto illustrata con cui compare in
/// "Vicinanze" (`NearbyRemoteDataSourceFakeImpl`), cosa ti propone e ciò che
/// mostra del profilo.
class FakeIncomingRequester {
  const FakeIncomingRequester({
    required this.personId,
    required this.proposal,
    this.selfieBytes,
    this.intent,
    this.languages = const [],
    this.visibleGender,
  });

  final String personId;
  final EncounterProposal proposal;
  final Uint8List? selfieBytes;
  final MeetIntent? intent;
  final List<String> languages;
  final Gender? visibleGender;
}
