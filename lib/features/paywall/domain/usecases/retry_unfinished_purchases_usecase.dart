import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/unlock_status.dart';
import '../repositories/store_repository.dart';
import 'redeem_store_purchase_usecase.dart';

/// Azione: riprova a riscattare gli acquisti pagati rimasti in sospeso in
/// questa esecuzione (il server non aveva risposto). `ProPaywall` la
/// chiama a ogni Start e a ogni controllo periodico dello stato: così uno
/// sblocco pagato arriva appena il server torna raggiungibile, senza
/// aspettare un riavvio. Un esito per acquisto (vuoto se non ce n'è).
class RetryUnfinishedPurchasesUseCase {
  const RetryUnfinishedPurchasesUseCase({
    required StoreRepository storeRepository,
    required RedeemStorePurchaseUseCase redeemStorePurchaseUseCase,
  }) : _storeRepository = storeRepository,
       _redeemStorePurchaseUseCase = redeemStorePurchaseUseCase;

  final StoreRepository _storeRepository;
  final RedeemStorePurchaseUseCase _redeemStorePurchaseUseCase;

  Future<List<Either<Failure, UnlockStatus>>> call() async => [
    for (final purchase in _storeRepository.unfinishedPurchases())
      await _redeemStorePurchaseUseCase(purchase),
  ];
}
