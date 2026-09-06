import 'dart:async';

import 'package:flutter/foundation.dart';

import '/core/usecases/usecase.dart';
import '../../domain/usecases/get_unlock_status_usecase.dart';
import '../../domain/usecases/purchase_unlock_usecase.dart';

/// Stato dello sblocco a pagamento: valido per 2 ore dall'acquisto
/// (`GetUnlockStatusUseCase`), poi torna a bloccare le persone più vicine.
/// Ricontrolla periodicamente (ogni 5 minuti) così lo sblocco scade da
/// solo in UI anche se l'app resta aperta oltre le 2 ore, senza bisogno
/// che qualcos'altro lo faccia scattare.
class ProPaywall extends ChangeNotifier {
  ProPaywall({
    required GetUnlockStatusUseCase getUnlockStatusUseCase,
    required PurchaseUnlockUseCase purchaseUnlockUseCase,
  }) : _getUnlockStatusUseCase = getUnlockStatusUseCase,
       _purchaseUnlockUseCase = purchaseUnlockUseCase {
    _refresh();
    _statusCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refresh(),
    );
  }

  final GetUnlockStatusUseCase _getUnlockStatusUseCase;
  final PurchaseUnlockUseCase _purchaseUnlockUseCase;

  Timer? _statusCheckTimer;
  bool _isUnlocked = false;
  bool _isPurchasing = false;
  String? _errorMessage;

  bool get isUnlocked => _isUnlocked;
  bool get isPurchasing => _isPurchasing;
  String? get errorMessage => _errorMessage;

  Future<void> _refresh() async {
    final result = await _getUnlockStatusUseCase(const NoParams());
    result.match(
      (failure) => _errorMessage = failure.message,
      (unlocked) => _isUnlocked = unlocked,
    );
    notifyListeners();
  }

  /// **Finto per ora**: vedi `PurchaseUnlockUseCase`.
  Future<void> purchase() async {
    _isPurchasing = true;
    notifyListeners();

    // Piccola pausa solo per far sentire che "sta succedendo qualcosa" —
    // un vero acquisto in-app avrebbe comunque una latenza simile.
    await Future<void>.delayed(const Duration(milliseconds: 800));

    final result = await _purchaseUnlockUseCase(const NoParams());
    result.match((failure) => _errorMessage = failure.message, (_) {
      _isUnlocked = true;
      _errorMessage = null;
    });

    _isPurchasing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }
}
