import 'package:flutter/foundation.dart';

import '/core/usecases/usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/end_session_usecase.dart';
import '/features/session/domain/usecases/get_current_session_usecase.dart';
import '/features/session/domain/usecases/start_session_usecase.dart';

/// Stato di sessione: online/offline, dati della sessione corrente.
/// `UiHome` osserva `isOnline` per decidere quale schermata mostrare.
class ProSession extends ChangeNotifier {
  ProSession({
    required GetCurrentSessionUseCase getCurrentSessionUseCase,
    required StartSessionUseCase startSessionUseCase,
    required EndSessionUseCase endSessionUseCase,
  }) : _getCurrentSessionUseCase = getCurrentSessionUseCase,
       _startSessionUseCase = startSessionUseCase,
       _endSessionUseCase = endSessionUseCase {
    _load();
  }

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final StartSessionUseCase _startSessionUseCase;
  final EndSessionUseCase _endSessionUseCase;

  bool _isLoading = true;
  OnlineSession? _session;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  OnlineSession? get session => _session;
  bool get isOnline => _session != null;
  String? get errorMessage => _errorMessage;

  Future<void> _load() async {
    final result = await _getCurrentSessionUseCase(const NoParams());
    result.match(
      (failure) => _errorMessage = failure.message,
      (session) => _session = session,
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<void> start(StartSessionParams params) async {
    final result = await _startSessionUseCase(params);
    result.match((failure) => _errorMessage = failure.message, (session) {
      _session = session;
      _errorMessage = null;
    });
    notifyListeners();
  }

  Future<void> end() async {
    await _endSessionUseCase(const NoParams());
    _session = null;
    notifyListeners();
  }
}
