import 'dart:async';
import 'dart:math';

import '../../domain/entities/encounter_request.dart';
import '../models/encounter_request_model.dart';
import 'encounter_remote_data_source.dart';

/// Implementazione **finta** (nessuna rete, nessun backend): tiene in
/// memoria le richieste in entrata/uscita, ogni tanto fa arrivare una
/// richiesta finta in entrata, e simula una risposta dopo qualche secondo a
/// quelle in uscita — applicando da sola la regola "un solo incontro alla
/// volta" quando è "l'altro" ad accettare, come farebbe un vero server.
class EncounterRemoteDataSourceFakeImpl implements EncounterRemoteDataSource {
  final Random _random = Random();
  final List<EncounterRequestModel> _incoming = [];
  final List<EncounterRequestModel> _outgoing = [];
  final StreamController<
    ({List<EncounterRequestModel> incoming, List<EncounterRequestModel> outgoing})
  >
  _controller = StreamController.broadcast();
  Timer? _incomingTimer;
  int _fakeIncomingCounter = 0;

  static const Duration _incomingTickInterval = Duration(seconds: 5);
  static const Duration _responseDelay = Duration(seconds: 4);
  static const double _newIncomingProbability = 0.3;
  static const double _acceptProbability = 0.6;

  bool get _hasActiveMatch =>
      _incoming.any((r) => r.status == EncounterRequestStatus.accepted) ||
      _outgoing.any((r) => r.status == EncounterRequestStatus.accepted);

  @override
  Stream<({List<EncounterRequestModel> incoming, List<EncounterRequestModel> outgoing})>
  watchRequests(String sessionId) {
    _incomingTimer ??= Timer.periodic(
      _incomingTickInterval,
      (_) => _maybeAddIncoming(),
    );
    scheduleMicrotask(_emit);
    return _controller.stream;
  }

  @override
  void sendRequest({required String otherPersonId}) {
    final request = EncounterRequestModel(
      id: 'out-${DateTime.now().microsecondsSinceEpoch}',
      otherPersonId: otherPersonId,
      otherSelfiePath: '',
      status: EncounterRequestStatus.pending,
    );
    _outgoing.add(request);
    _emit();

    Timer(_responseDelay, () {
      final index = _outgoing.indexWhere((r) => r.id == request.id);
      if (index == -1 ||
          _outgoing[index].status != EncounterRequestStatus.pending) {
        return;
      }
      final accepted = _random.nextDouble() < _acceptProbability;
      _outgoing[index] = EncounterRequestModel(
        id: _outgoing[index].id,
        otherPersonId: _outgoing[index].otherPersonId,
        otherSelfiePath: _outgoing[index].otherSelfiePath,
        status: accepted
            ? EncounterRequestStatus.accepted
            : EncounterRequestStatus.declined,
      );
      if (accepted) _cancelOtherPending(exceptId: request.id);
      _emit();
    });
  }

  @override
  void respondToRequest({required String requestId, required bool accepted}) {
    final index = _incoming.indexWhere((r) => r.id == requestId);
    if (index == -1) return;

    _incoming[index] = EncounterRequestModel(
      id: _incoming[index].id,
      otherPersonId: _incoming[index].otherPersonId,
      otherSelfiePath: _incoming[index].otherSelfiePath,
      status: accepted
          ? EncounterRequestStatus.accepted
          : EncounterRequestStatus.declined,
    );
    if (accepted) _cancelOtherPending(exceptId: requestId);
    _emit();
  }

  @override
  void endMatch(String requestId) {
    final incomingIndex = _incoming.indexWhere((r) => r.id == requestId);
    if (incomingIndex != -1) {
      _incoming[incomingIndex] = EncounterRequestModel(
        id: _incoming[incomingIndex].id,
        otherPersonId: _incoming[incomingIndex].otherPersonId,
        otherSelfiePath: _incoming[incomingIndex].otherSelfiePath,
        status: EncounterRequestStatus.ended,
      );
      _emit();
      return;
    }

    final outgoingIndex = _outgoing.indexWhere((r) => r.id == requestId);
    if (outgoingIndex != -1) {
      _outgoing[outgoingIndex] = EncounterRequestModel(
        id: _outgoing[outgoingIndex].id,
        otherPersonId: _outgoing[outgoingIndex].otherPersonId,
        otherSelfiePath: _outgoing[outgoingIndex].otherSelfiePath,
        status: EncounterRequestStatus.ended,
      );
      _emit();
    }
  }

  void _maybeAddIncoming() {
    final hasPending = _incoming.any(
      (r) => r.status == EncounterRequestStatus.pending,
    );
    if (hasPending || _hasActiveMatch) return;
    if (_random.nextDouble() >= _newIncomingProbability) return;

    _fakeIncomingCounter++;
    _incoming.add(
      EncounterRequestModel(
        id: 'in-$_fakeIncomingCounter-${DateTime.now().microsecondsSinceEpoch}',
        otherPersonId: 'fake-person-$_fakeIncomingCounter',
        otherSelfiePath: '',
        status: EncounterRequestStatus.pending,
      ),
    );
    _emit();
  }

  void _cancelOtherPending({required String exceptId}) {
    for (var i = 0; i < _incoming.length; i++) {
      if (_incoming[i].id != exceptId &&
          _incoming[i].status == EncounterRequestStatus.pending) {
        _incoming[i] = EncounterRequestModel(
          id: _incoming[i].id,
          otherPersonId: _incoming[i].otherPersonId,
          otherSelfiePath: _incoming[i].otherSelfiePath,
          status: EncounterRequestStatus.cancelled,
        );
      }
    }
    for (var i = 0; i < _outgoing.length; i++) {
      if (_outgoing[i].id != exceptId &&
          _outgoing[i].status == EncounterRequestStatus.pending) {
        _outgoing[i] = EncounterRequestModel(
          id: _outgoing[i].id,
          otherPersonId: _outgoing[i].otherPersonId,
          otherSelfiePath: _outgoing[i].otherSelfiePath,
          status: EncounterRequestStatus.cancelled,
        );
      }
    }
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add((
      incoming: List.unmodifiable(_incoming),
      outgoing: List.unmodifiable(_outgoing),
    ));
  }
}
