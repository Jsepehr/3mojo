import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/encounter_request.dart';
import '../../domain/usecases/end_match_usecase.dart';
import '../../domain/usecases/get_incoming_requests_usecase.dart';
import '../../domain/usecases/get_outgoing_requests_usecase.dart';
import '../../domain/usecases/respond_to_encounter_request_usecase.dart';
import '../../domain/usecases/send_encounter_request_usecase.dart';

class ProEncounters extends ChangeNotifier {
  ProEncounters({
    required SendEncounterRequestUseCase sendEncounterRequestUseCase,
    required GetIncomingRequestsUseCase getIncomingRequestsUseCase,
    required GetOutgoingRequestsUseCase getOutgoingRequestsUseCase,
    required RespondToEncounterRequestUseCase respondToEncounterRequestUseCase,
    required EndMatchUseCase endMatchUseCase,
  }) : _sendEncounterRequestUseCase = sendEncounterRequestUseCase,
       _getIncomingRequestsUseCase = getIncomingRequestsUseCase,
       _getOutgoingRequestsUseCase = getOutgoingRequestsUseCase,
       _respondToEncounterRequestUseCase = respondToEncounterRequestUseCase,
       _endMatchUseCase = endMatchUseCase {
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  final SendEncounterRequestUseCase _sendEncounterRequestUseCase;
  final GetIncomingRequestsUseCase _getIncomingRequestsUseCase;
  final GetOutgoingRequestsUseCase _getOutgoingRequestsUseCase;
  final RespondToEncounterRequestUseCase _respondToEncounterRequestUseCase;
  final EndMatchUseCase _endMatchUseCase;

  Timer? _pollTimer;
  List<EncounterRequest> _incomingRequests = [];
  List<EncounterRequest> _outgoingRequests = [];
  String? _errorMessage;

  List<EncounterRequest> get incomingRequests => _incomingRequests;
  List<EncounterRequest> get outgoingRequests => _outgoingRequests;
  String? get errorMessage => _errorMessage;

  int get pendingIncomingCount => _incomingRequests
      .where((r) => r.status == EncounterRequestStatus.pending)
      .length;

  EncounterRequest? get activeMatch {
    for (final request in [..._incomingRequests, ..._outgoingRequests]) {
      if (request.status == EncounterRequestStatus.accepted) return request;
    }
    return null;
  }

  Future<void> _refresh() async {
    final incomingResult = await _getIncomingRequestsUseCase(const NoParams());
    incomingResult.match(
      (failure) => _errorMessage = failure.message,
      (requests) => _incomingRequests = requests,
    );

    final outgoingResult = await _getOutgoingRequestsUseCase(const NoParams());
    outgoingResult.match(
      (failure) => _errorMessage = failure.message,
      (requests) => _outgoingRequests = requests,
    );

    notifyListeners();
  }

  Future<void> sendRequest(String otherPersonId, String otherSelfiePath) async {
    final result = await _sendEncounterRequestUseCase(
      SendEncounterRequestParams(
        otherPersonId: otherPersonId,
        otherSelfiePath: otherSelfiePath,
      ),
    );
    result.match(
      (failure) => _errorMessage = failure.message,
      (request) => _outgoingRequests = [..._outgoingRequests, request],
    );
    notifyListeners();
  }

  Future<void> respondToRequest(String requestId, bool accepted) async {
    final result = await _respondToEncounterRequestUseCase(
      RespondToEncounterRequestParams(requestId: requestId, accepted: accepted),
    );
    result.match((failure) => _errorMessage = failure.message, (updated) {
      _incomingRequests = [
        for (final r in _incomingRequests)
          if (r.id == requestId) updated else r,
      ];
    });
    await _refresh();
  }

  Future<void> endMatch(String requestId) async {
    await _endMatchUseCase(requestId);
    await _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
