import 'package:flutter/foundation.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../../domain/usecases/check_demo_available_usecase.dart';

/// Se la **demo dichiarata** è aperta. Vive nel mondo reale (provider di
/// `App`): quando [isActive] è `true`, `RaenApp` mette `DemoScope` sopra
/// tutte le pagine — i provider della demo (datasource finti, sessione in
/// memoria tutta sua) coprono quelli reali, che restano fermi e intatti
/// sotto. Uscendo ([leave]) `DemoScope` sparisce con tutto ciò che conteneva.
///
/// Se si può entrare lo decide `CheckDemoAvailableUseCase` (solo da
/// offline); qui solo lo stato.
class ProDemo extends ChangeNotifier {
  ProDemo({required CheckDemoAvailableUseCase checkDemoAvailableUseCase})
    : _checkDemoAvailableUseCase = checkDemoAvailableUseCase;

  final CheckDemoAvailableUseCase _checkDemoAvailableUseCase;
  bool _isActive = false;
  bool _isEntering = false;

  bool get isActive => _isActive;

  /// Apre la demo. Ritorna perché non si può (es.
  /// `DemoUnavailableDuringSessionFailure`), o `null` se è aperta (o lo era
  /// già, o si sta già aprendo).
  Future<Failure?> enter() async {
    if (_isActive || _isEntering) return null;
    _isEntering = true;
    final result = await _checkDemoAvailableUseCase(const NoParams());
    _isEntering = false;
    return result.match((failure) => failure, (_) {
      _isActive = true;
      notifyListeners();
      return null;
    });
  }

  /// Chiude la demo: la chiama `DemoScope` quando la sessione della demo è
  /// già finita (passi di pulizia fatti) e le sue pagine sono chiuse.
  void leave() {
    if (!_isActive) return;
    _isActive = false;
    notifyListeners();
  }
}
