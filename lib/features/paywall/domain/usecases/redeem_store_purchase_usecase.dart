import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/store_purchase.dart';
import '../entities/unlock_status.dart';
import '../repositories/paywall_repository.dart';
import '../repositories/store_repository.dart';
import 'resolve_unlock_expiry_usecase.dart';

/// Azione: trasforma un acquisto pagato nel negozio in uno sblocco — il
/// passo comune all'acquisto appena fatto (`PurchaseUnlockUseCase`) e a
/// quelli rimasti in sospeso (`WatchUnfinishedPurchasesUseCase`,
/// `RetryUnfinishedPurchasesUseCase`).
///
/// Regole:
/// - l'acquisto si **completa nel negozio solo dopo** che il server l'ha
///   verificato e ha emesso lo sblocco: se il server non risponde, il
///   negozio lo ripresenterà (anche dopo un riavvio) e si riprova — il
///   server è idempotente e ridà lo stesso sblocco;
/// - già riscattato (sblocco finito) → si completa comunque: era già stato
///   consegnato;
/// - rifiutato dal server dopo la verifica col negozio → **non** si
///   completa (su Google Play un acquisto mai confermato è rimborsato da
///   Google), nessuno sblocco;
/// - qualsiasi altro errore (rete, server, negozio lento) →
///   `UnlockNotDeliveredYetFailure`: pagato, sblocco in arrivo;
/// - lo stesso acquisto non viene riscattato due volte in parallelo
///   (es. arriva dallo stream mentre si sta già riprovando): la seconda
///   chiamata aspetta l'esito della prima.
///
/// Un'istanza sola condivisa dai tre use case (vedi `app.dart`), perché la
/// deduplica funzioni tra loro.
class RedeemStorePurchaseUseCase {
  RedeemStorePurchaseUseCase({
    required PaywallRepository paywallRepository,
    required StoreRepository storeRepository,
    ResolveUnlockExpiryUseCase? resolveUnlockExpiryUseCase,
  }) : _paywallRepository = paywallRepository,
       _storeRepository = storeRepository,
       _resolveUnlockExpiryUseCase =
           resolveUnlockExpiryUseCase ?? ResolveUnlockExpiryUseCase();

  final PaywallRepository _paywallRepository;
  final StoreRepository _storeRepository;
  final ResolveUnlockExpiryUseCase _resolveUnlockExpiryUseCase;
  final Map<StorePurchase, Future<Either<Failure, UnlockStatus>>> _inFlight =
      {};

  Future<Either<Failure, UnlockStatus>> call(StorePurchase purchase) {
    final running = _inFlight[purchase];
    if (running != null) return running;
    // Corpo a blocco: `remove` ritorna proprio questo future, e
    // `whenComplete` aspetterebbe sé stesso.
    final future = _redeem(purchase).whenComplete(() {
      _inFlight.remove(purchase);
    });
    _inFlight[purchase] = future;
    return future;
  }

  Future<Either<Failure, UnlockStatus>> _redeem(StorePurchase purchase) async {
    final redeemed = await _paywallRepository.redeemPurchase(purchase);
    switch (redeemed) {
      case Right(value: final remaining):
        // Se il completamento fallisce, il negozio lo ripresenterà e il
        // server ridarà lo stesso sblocco: non è un errore da mostrare.
        await _storeRepository.completePurchase(purchase);
        return Right(_resolveUnlockExpiryUseCase(remaining));
      case Left(value: PurchaseAlreadyRedeemedFailure() && final failure):
        await _storeRepository.completePurchase(purchase);
        return Left(failure);
      case Left(value: PurchaseNotVerifiedFailure() && final failure):
        return Left(failure);
      case Left():
        return const Left(UnlockNotDeliveredYetFailure());
    }
  }
}
