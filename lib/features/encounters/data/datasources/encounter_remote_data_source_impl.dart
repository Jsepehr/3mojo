import 'dart:math';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/encounter_request.dart';
import '../models/encounter_request_model.dart';
import 'encounter_remote_data_source.dart';

class EncounterRemoteDataSourceImpl implements EncounterRemoteDataSource {
  final Random _random = Random();
  final List<EncounterRequestModel> _incoming = [];
  final List<EncounterRequestModel> _outgoing = [];
  int _fakeIncomingCounter = 0;

  bool get _hasActiveMatch =>
      _incoming.any((r) => r.status == EncounterRequestStatus.accepted) ||
      _outgoing.any((r) => r.status == EncounterRequestStatus.accepted);

  @override
  Future<EncounterRequestModel> sendRequest({
    required String otherPersonId,
    required String otherSelfiePath,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final request = EncounterRequestModel(
      id: 'out-${DateTime.now().microsecondsSinceEpoch}',
      otherPersonId: otherPersonId,
      otherSelfiePath: otherSelfiePath,
      status: EncounterRequestStatus.pending,
    );
    _outgoing.add(request);

    // Simulates the other phone answering a few seconds later. A real
    // backend would enforce single-match exclusivity itself when it
    // pushes this outcome, so the fake does the same here.
    Future<void>.delayed(const Duration(seconds: 4), () {
      final index = _outgoing.indexWhere((r) => r.id == request.id);
      if (index == -1 ||
          _outgoing[index].status != EncounterRequestStatus.pending) {
        return;
      }
      final accepted = _random.nextDouble() < 0.6;
      _outgoing[index] = _outgoing[index].copyWith(
        status: accepted
            ? EncounterRequestStatus.accepted
            : EncounterRequestStatus.declined,
      );
      if (accepted) {
        _cancelOtherPending(exceptId: request.id);
      }
    });

    return request;
  }

  @override
  Future<List<EncounterRequestModel>> getIncomingRequests() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final hasPending = _incoming.any(
      (r) => r.status == EncounterRequestStatus.pending,
    );
    if (!hasPending && !_hasActiveMatch && _random.nextDouble() < 0.4) {
      _fakeIncomingCounter++;
      _incoming.add(
        EncounterRequestModel(
          id: 'in-$_fakeIncomingCounter',
          otherPersonId: 'fake-person-$_fakeIncomingCounter',
          otherSelfiePath: '',
          status: EncounterRequestStatus.pending,
        ),
      );
    }

    return List.unmodifiable(_incoming);
  }

  @override
  Future<List<EncounterRequestModel>> getOutgoingRequests() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_outgoing);
  }

  @override
  Future<EncounterRequestModel> respondToRequest({
    required String requestId,
    required bool accepted,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final index = _incoming.indexWhere((r) => r.id == requestId);
    if (index == -1) {
      throw const ServerException('Richiesta non trovata');
    }

    _incoming[index] = _incoming[index].copyWith(
      status: accepted
          ? EncounterRequestStatus.accepted
          : EncounterRequestStatus.declined,
    );
    return _incoming[index];
  }

  @override
  Future<void> cancelOtherPendingRequests(String exceptRequestId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _cancelOtherPending(exceptId: exceptRequestId);
  }

  @override
  Future<void> endMatch(String requestId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final incomingIndex = _incoming.indexWhere((r) => r.id == requestId);
    if (incomingIndex != -1) {
      _incoming[incomingIndex] = _incoming[incomingIndex].copyWith(
        status: EncounterRequestStatus.ended,
      );
      return;
    }

    final outgoingIndex = _outgoing.indexWhere((r) => r.id == requestId);
    if (outgoingIndex != -1) {
      _outgoing[outgoingIndex] = _outgoing[outgoingIndex].copyWith(
        status: EncounterRequestStatus.ended,
      );
      return;
    }

    throw const ServerException('Richiesta non trovata');
  }

  void _cancelOtherPending({required String exceptId}) {
    for (var i = 0; i < _incoming.length; i++) {
      if (_incoming[i].id != exceptId &&
          _incoming[i].status == EncounterRequestStatus.pending) {
        _incoming[i] = _incoming[i].copyWith(
          status: EncounterRequestStatus.cancelled,
        );
      }
    }
    for (var i = 0; i < _outgoing.length; i++) {
      if (_outgoing[i].id != exceptId &&
          _outgoing[i].status == EncounterRequestStatus.pending) {
        _outgoing[i] = _outgoing[i].copyWith(
          status: EncounterRequestStatus.cancelled,
        );
      }
    }
  }
}
