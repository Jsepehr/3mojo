import 'dart:async';

import 'package:flutter/foundation.dart';

import '/core/usecases/usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/end_session_usecase.dart';
import '/features/session/domain/usecases/watch_session_usecase.dart';
import '../../domain/usecases/start_demo_session_usecase.dart';

/// Il giro della **demo dichiarata**, dentro `DemoScope` (mondo della demo:
/// i suoi use case lavorano solo sui repository della demo). Appena creato
/// fa partire la sessione della demo (`StartDemoSessionUseCase`); [exit]
/// la chiude con `EndSessionUseCase` della demo — gli stessi passi di
/// pulizia di End (visibilità, richieste, chat, blocchi), ma sui datasource
/// finti della demo.
///
/// [isFinished] diventa `true` quando la sessione della demo è finita, da
/// qualunque parte (bottone "Esci dalla demo" del banner, End nell'AppBar)
/// o se non è potuta partire: allora `DemoScope` chiude le pagine della
/// demo e la chiude (`ProDemo.leave`).
class ProDemoTour extends ChangeNotifier {
  ProDemoTour({
    required StartDemoSessionUseCase startDemoSessionUseCase,
    required EndSessionUseCase endSessionUseCase,
    required WatchSessionUseCase watchSessionUseCase,
  }) : _endSessionUseCase = endSessionUseCase {
    _sessionSubscription = watchSessionUseCase().listen(_onSession);
    unawaited(_start(startDemoSessionUseCase));
  }

  final EndSessionUseCase _endSessionUseCase;
  late final StreamSubscription<OnlineSession?> _sessionSubscription;
  bool _hasStarted = false;
  bool _isExiting = false;
  bool _isFinished = false;
  bool _disposed = false;

  /// `true` da quando si è chiesto di uscire: il bottone si disattiva.
  bool get isExiting => _isExiting;

  /// La sessione della demo è finita: la demo va chiusa.
  bool get isFinished => _isFinished;

  Future<void> _start(StartDemoSessionUseCase startDemoSessionUseCase) async {
    final result = await startDemoSessionUseCase(const NoParams());
    if (_disposed) return;
    result.match((_) => _finish(), (_) {});
  }

  void _onSession(OnlineSession? session) {
    if (session != null) {
      _hasStarted = true;
    } else if (_hasStarted) {
      _finish();
    }
  }

  /// Esci dalla demo: chiude la sessione della demo e azzera tutto ciò che
  /// aveva (i passi di pulizia di End).
  Future<void> exit() async {
    if (_isExiting || _isFinished) return;
    _isExiting = true;
    notifyListeners();
    if (_hasStarted) await _endSessionUseCase(const NoParams());
    if (_disposed) return;
    _finish();
  }

  void _finish() {
    if (_isFinished) return;
    _isFinished = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionSubscription.cancel();
    super.dispose();
  }
}
