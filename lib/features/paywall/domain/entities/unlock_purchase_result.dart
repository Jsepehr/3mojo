import 'package:equatable/equatable.dart';

import 'unlock_status.dart';

/// Esito di "compra lo sblocco" (`PurchaseUnlockUseCase`).
sealed class UnlockPurchaseResult extends Equatable {
  const UnlockPurchaseResult();
}

/// Pagato e confermato dal server: sbloccato fino a [status].
class UnlockPurchased extends UnlockPurchaseResult {
  const UnlockPurchased(this.status);

  final UnlockStatus status;

  @override
  List<Object?> get props => [status];
}

/// Il negozio aspetta il pagamento (contanti, approvazione di un genitore):
/// lo sblocco arriverà da solo quando il negozio lo conferma
/// (`WatchUnfinishedPurchasesUseCase`).
class UnlockPurchasePending extends UnlockPurchaseResult {
  const UnlockPurchasePending();

  @override
  List<Object?> get props => [];
}
