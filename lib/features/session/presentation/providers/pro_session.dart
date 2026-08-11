import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '/core/usecases/usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/check_selfie_has_face_usecase.dart';
import '/features/session/domain/usecases/end_session_usecase.dart';
import '/features/session/domain/usecases/get_current_session_usecase.dart';
import '/features/session/domain/usecases/start_session_usecase.dart';

/// Stato di sessione: online/offline, dati della sessione corrente.
/// `UiHome` osserva `isOnline` per decidere quale schermata mostrare.
/// Mentre si è online, impedisce anche lo standby dello schermo
/// (`WakelockPlus`) — si guarda il telefono in mano camminando, non ha
/// senso che si spenga da solo; da offline torna al comportamento normale.
class ProSession extends ChangeNotifier {
  ProSession({
    required GetCurrentSessionUseCase getCurrentSessionUseCase,
    required StartSessionUseCase startSessionUseCase,
    required EndSessionUseCase endSessionUseCase,
    required CheckSelfieHasFaceUseCase checkSelfieHasFaceUseCase,
  }) : _getCurrentSessionUseCase = getCurrentSessionUseCase,
       _startSessionUseCase = startSessionUseCase,
       _endSessionUseCase = endSessionUseCase,
       _checkSelfieHasFaceUseCase = checkSelfieHasFaceUseCase {
    _load();
  }

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final StartSessionUseCase _startSessionUseCase;
  final EndSessionUseCase _endSessionUseCase;
  final CheckSelfieHasFaceUseCase _checkSelfieHasFaceUseCase;

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

    if (_session != null) await WakelockPlus.enable();

    _isLoading = false;
    notifyListeners();
  }

  /// Controllo "a caldo" chiamato dal wizard subito dopo lo scatto, per un
  /// feedback immediato — la validazione vera e autorevole resta comunque
  /// dentro `StartSessionUseCase`, chiamata di nuovo al submit finale.
  Future<bool> checkSelfieHasFace(String selfiePath) async {
    final result = await _checkSelfieHasFaceUseCase(selfiePath);
    final hasFace = result.match(
      (failure) {
        _errorMessage = failure.message;
        return false;
      },
      (_) {
        _errorMessage = null;
        return true;
      },
    );

    notifyListeners();
    return hasFace;
  }

  Future<void> start(StartSessionParams params) async {
    final result = await _startSessionUseCase(params);
    result.match((failure) => _errorMessage = failure.message, (session) {
      _session = session;
      _errorMessage = null;
    });

    if (_session != null) await WakelockPlus.enable();

    notifyListeners();
  }

  Future<void> end() async {
    await _endSessionUseCase(const NoParams());
    _session = null;
    await WakelockPlus.disable();
    notifyListeners();
  }
}
