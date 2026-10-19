import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/watch_session_usecase.dart';
import '../../domain/usecases/get_unlock_status_usecase.dart';
import '../../domain/usecases/purchase_unlock_usecase.dart';

/// Stato dello sblocco a pagamento: valido per 2 ore dall'acquisto
/// (`GetUnlockStatusUseCase`), poi torna a bloccare le persone più vicine.
///
/// **Interroga il server solo da online**, guidato dal ciclo di vita della
/// sessione (`WatchSessionUseCase`): a ogni Start controlla lo stato e
/// ricontrolla ogni 5 minuti (così lo sblocco scade da solo in UI anche se
/// l'app resta aperta oltre le 2 ore); a End il controllo periodico si
/// ferma. Un controllo fallito non cambia nulla (si riprova al prossimo
/// giro): non c'è niente da far fare all'utente.
class ProPaywall extends ChangeNotifier {
  ProPaywall({
    required WatchSessionUseCase watchSessionUseCase,
    required GetUnlockStatusUseCase getUnlockStatusUseCase,
    required PurchaseUnlockUseCase purchaseUnlockUseCase,
    Duration purchaseFeedbackDelay = const Duration(milliseconds: 800),
  }) : _getUnlockStatusUseCase = getUnlockStatusUseCase,
       _purchaseUnlockUseCase = purchaseUnlockUseCase,
       _purchaseFeedbackDelay = purchaseFeedbackDelay {
    _sessionSubscription = watchSessionUseCase().listen(_onSession);
  }

  static const Duration _statusCheckInterval = Duration(minutes: 5);

  final GetUnlockStatusUseCase _getUnlockStatusUseCase;
  final PurchaseUnlockUseCase _purchaseUnlockUseCase;
  final Duration _purchaseFeedbackDelay;

  late final StreamSubscription<OnlineSession?> _sessionSubscription;
  Timer? _statusCheckTimer;
  bool _isOnline = false;
  bool _isUnlocked = false;
  bool _isPurchasing = false;
  bool _disposed = false;

  bool get isUnlocked => _isUnlocked;
  bool get isPurchasing => _isPurchasing;

  void _onSession(OnlineSession? session) {
    final isOnline = session != null;
    if (isOnline == _isOnline) return;
    _isOnline = isOnline;

    _statusCheckTimer?.cancel();
    _statusCheckTimer = null;
    if (isOnline) {
      _refresh();
      _statusCheckTimer = Timer.periodic(
        _statusCheckInterval,
        (_) => _refresh(),
      );
    }
  }

  Future<void> _refresh() async {
    final result = await _getUnlockStatusUseCase(const NoParams());
    if (_disposed) return;
    result.match((_) {}, (unlocked) {
      if (unlocked == _isUnlocked) return;
      _isUnlocked = unlocked;
      notifyListeners();
    });
  }

  /// **Finto per ora**: vedi `PurchaseUnlockUseCase`. Ritorna l'esito
  /// (`Right` = sbloccato), o `null` se un acquisto era già in corso e
  /// questa chiamata è stata ignorata (niente doppio acquisto).
  Future<Either<Failure, Unit>?> purchase() async {
    if (_isPurchasing) return null;
    _isPurchasing = true;
    notifyListeners();

    // Piccola pausa solo per far sentire che "sta succedendo qualcosa" —
    // un vero acquisto in-app avrebbe comunque una latenza simile.
    await Future<void>.delayed(_purchaseFeedbackDelay);

    final result = await _purchaseUnlockUseCase(const NoParams());
    if (result.isRight()) _isUnlocked = true;

    _isPurchasing = false;
    if (!_disposed) notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionSubscription.cancel();
    _statusCheckTimer?.cancel();
    super.dispose();
  }
}
