import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/unlock_status.dart';
import '../repositories/store_repository.dart';
import 'redeem_store_purchase_usecase.dart';

/// Azione: riscatta da solo ogni acquisto pagato che il negozio presenta
/// fuori dalla finestra d'acquisto — rimasto aperto dall'esecuzione
/// precedente (app chiusa o server muto prima della conferma), un
/// pagamento in attesa diventato confermato, un acquisto ripresentato.
/// Ogni esito arriva sullo stream (uno sblocco, o perché non è arrivato).
///
/// Va ascoltato dall'avvio dell'app (`ProPaywall`), non solo da online:
/// il negozio presenta questi acquisti appena l'app parte.
class WatchUnfinishedPurchasesUseCase {
  const WatchUnfinishedPurchasesUseCase({
    required StoreRepository storeRepository,
    required RedeemStorePurchaseUseCase redeemStorePurchaseUseCase,
  }) : _storeRepository = storeRepository,
       _redeemStorePurchaseUseCase = redeemStorePurchaseUseCase;

  final StoreRepository _storeRepository;
  final RedeemStorePurchaseUseCase _redeemStorePurchaseUseCase;

  Stream<Either<Failure, UnlockStatus>> call() => _storeRepository
      .watchUnfinishedPurchases()
      .asyncMap(_redeemStorePurchaseUseCase.call);
}
