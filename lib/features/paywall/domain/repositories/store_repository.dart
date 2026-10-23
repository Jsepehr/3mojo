import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/store_checkout.dart';
import '../entities/store_purchase.dart';
import '../entities/unlock_offer.dart';

/// Contratto verso il **negozio** (App Store / Google Play, o quello
/// simulato nei build di debug): vende lo sblocco e tiene gli acquisti
/// finché non vengono completati. Non sa nulla del server: verificare e
/// sbloccare è di `PaywallRepository`, l'ordine dei passi è degli use case.
abstract class StoreRepository {
  /// Il prodotto e il suo prezzo, o `StoreUnavailableFailure`.
  Future<Either<Failure, UnlockOffer>> getUnlockOffer();

  /// Apre la finestra del negozio e aspetta com'è finita:
  /// `PurchaseCanceledFailure`, `StorePurchaseFailure`,
  /// `StoreUnavailableFailure` o un [StoreCheckout].
  Future<Either<Failure, StoreCheckout>> buyUnlock();

  /// Gli acquisti pagati che arrivano **fuori** da [buyUnlock]: rimasti non
  /// completati dall'esecuzione precedente, un pagamento in attesa
  /// diventato confermato, un acquisto fatto dal negozio stesso.
  Stream<StorePurchase> watchUnfinishedPurchases();

  /// Quelli visti in questa esecuzione e non ancora completati (per
  /// riprovare a riscattarli).
  List<StorePurchase> unfinishedPurchases();

  /// Chiude l'acquisto nel negozio (consumabile: si potrà ricomprare). Da
  /// chiamare **solo dopo** che il server ha confermato lo sblocco.
  Future<Either<Failure, Unit>> completePurchase(StorePurchase purchase);
}
