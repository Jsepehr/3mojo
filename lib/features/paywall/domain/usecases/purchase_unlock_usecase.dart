import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/store_checkout.dart';
import '../entities/unlock_purchase_result.dart';
import '../repositories/store_repository.dart';
import 'redeem_store_purchase_usecase.dart';

/// Azione: compra lo sblocco di 2 ore con un acquisto in-app (App Store /
/// Google Play; nei build di debug il negozio simulato) e lo riscatta sul
/// server, che lo verifica col negozio prima di sbloccare.
///
/// Regole:
/// - **niente doppio addebito**: se c'è già un acquisto pagato e non ancora
///   riscattato (es. il server non aveva risposto), prima si riprova
///   quello; solo se non vale (rifiutato o già usato) si apre il negozio;
/// - annullato nel negozio → `PurchaseCanceledFailure` (la UI non dice
///   nulla), errore → `StorePurchaseFailure`, negozio non disponibile →
///   `StoreUnavailableFailure`;
/// - pagamento in attesa (contanti, genitori) → [UnlockPurchasePending]:
///   lo sblocco arriverà da solo (`WatchUnfinishedPurchasesUseCase`);
/// - pagato → `RedeemStorePurchaseUseCase` (verifica sul server, poi
///   completamento nel negozio).
class PurchaseUnlockUseCase implements UseCase<UnlockPurchaseResult, NoParams> {
  const PurchaseUnlockUseCase({
    required StoreRepository storeRepository,
    required RedeemStorePurchaseUseCase redeemStorePurchaseUseCase,
  }) : _storeRepository = storeRepository,
       _redeemStorePurchaseUseCase = redeemStorePurchaseUseCase;

  final StoreRepository _storeRepository;
  final RedeemStorePurchaseUseCase _redeemStorePurchaseUseCase;

  @override
  Future<Either<Failure, UnlockPurchaseResult>> call(NoParams params) async {
    for (final unfinished in _storeRepository.unfinishedPurchases()) {
      final redeemed = await _redeemStorePurchaseUseCase(unfinished);
      switch (redeemed) {
        case Right(value: final status):
          return Right(UnlockPurchased(status));
        case Left(value: UnlockNotDeliveredYetFailure() && final failure):
          // Già pagato, il server non risponde: farlo pagare di nuovo
          // sarebbe un doppio addebito.
          return Left(failure);
        case Left():
          continue;
      }
    }

    final checkout = await _storeRepository.buyUnlock();
    switch (checkout) {
      case Left(value: final failure):
        return Left(failure);
      case Right(value: StoreCheckoutPending()):
        return const Right(UnlockPurchasePending());
      case Right(value: StoreCheckoutPurchased(:final purchase)):
        return (await _redeemStorePurchaseUseCase(
          purchase,
        )).map(UnlockPurchased.new);
    }
  }
}
