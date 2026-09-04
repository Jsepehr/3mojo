import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/encounter_request.dart';
import '../../domain/usecases/end_match_usecase.dart';
import '../../domain/usecases/respond_to_encounter_request_usecase.dart';
import '../../domain/usecases/send_encounter_request_usecase.dart';
import '../../domain/usecases/watch_encounter_requests_usecase.dart';

/// Stato di richieste in entrata/uscita — spinte dal server sulla
/// connessione condivisa con `nearby`, non più richieste con un polling
/// ogni 3s. Come `ProNearby`, lo stream finisce prima o poi (offline,
/// connessione caduta) e ci si riabbona da soli. `activeMatch` espone la
/// prima richiesta accettata trovata — usata da `_MatchGate` in app.dart
/// per aprire la pagina di chat a schermo intero.
class ProEncounters extends ChangeNotifier {
  ProEncounters({
    required WatchEncounterRequestsUseCase watchEncounterRequestsUseCase,
    required SendEncounterRequestUseCase sendEncounterRequestUseCase,
    required RespondToEncounterRequestUseCase respondToEncounterRequestUseCase,
    required EndMatchUseCase endMatchUseCase,
  }) : _watchEncounterRequestsUseCase = watchEncounterRequestsUseCase,
       _sendEncounterRequestUseCase = sendEncounterRequestUseCase,
       _respondToEncounterRequestUseCase = respondToEncounterRequestUseCase,
       _endMatchUseCase = endMatchUseCase {
    _subscribe();
  }

  static const Duration _resubscribeDelay = Duration(seconds: 3);

  final WatchEncounterRequestsUseCase _watchEncounterRequestsUseCase;
  final SendEncounterRequestUseCase _sendEncounterRequestUseCase;
  final RespondToEncounterRequestUseCase _respondToEncounterRequestUseCase;
  final EndMatchUseCase _endMatchUseCase;

  StreamSubscription<void>? _subscription;
  Timer? _resubscribeTimer;
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

  void _subscribe() {
    _subscription = _watchEncounterRequestsUseCase().listen(
      (result) {
        result.match((failure) => _errorMessage = failure.message, (
          snapshot,
        ) {
          _incomingRequests = snapshot.incoming;
          _outgoingRequests = snapshot.outgoing;
          _errorMessage = null;
        });
        notifyListeners();
      },
      onError: (Object error) {
        _errorMessage = error.toString();
        notifyListeners();
      },
      onDone: _scheduleResubscribe,
    );
  }

  void _scheduleResubscribe() {
    _resubscribeTimer = Timer(_resubscribeDelay, _subscribe);
  }

  void sendRequest(String otherPersonId) =>
      _sendEncounterRequestUseCase(otherPersonId);

  void respondToRequest(String requestId, bool accepted) =>
      _respondToEncounterRequestUseCase(
        RespondToEncounterRequestParams(
          requestId: requestId,
          accepted: accepted,
        ),
      );

  void endMatch({required String requestId, required String otherPersonId}) =>
      _endMatchUseCase(requestId: requestId, otherPersonId: otherPersonId);

  @override
  void dispose() {
    _resubscribeTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
