import 'package:fpdart/fpdart.dart';

import '/core/errors/exceptions.dart';
import '/core/errors/failures.dart';
import '../../domain/entities/store_checkout.dart';
import '../../domain/entities/store_purchase.dart';
import '../../domain/entities/unlock_offer.dart';
import '../../domain/repositories/store_repository.dart';
import '../datasources/store_billing_data_source.dart';

/// Mantiene la promessa di [StoreRepository] col negozio scelto all'avvio
/// (reale, simulato o non disponibile, vedi `StoreConfig.mode`), traducendo
/// le sue eccezioni in `Failure` tipizzati.
class StoreRepositoryImpl implements StoreRepository {
  const StoreRepositoryImpl(this._dataSource);

  final StoreBillingDataSource _dataSource;

  @override
  Future<Either<Failure, UnlockOffer>> getUnlockOffer() async {
    try {
      return Right(await _dataSource.loadUnlockOffer());
    } on StoreUnavailableException catch (e) {
      return Left(StoreUnavailableFailure(e.message));
    } catch (e) {
      return Left(StoreUnavailableFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, StoreCheckout>> buyUnlock() async {
    try {
      return Right(await _dataSource.buyUnlock());
    } on PurchaseCanceledException {
      return const Left(PurchaseCanceledFailure());
    } on StoreUnavailableException catch (e) {
      return Left(StoreUnavailableFailure(e.message));
    } on StorePurchaseException catch (e) {
      return Left(StorePurchaseFailure(e.message));
    } catch (e) {
      return Left(StorePurchaseFailure(e.toString()));
    }
  }

  @override
  Stream<StorePurchase> watchUnfinishedPurchases() =>
      _dataSource.unfinishedPurchases;

  @override
  List<StorePurchase> unfinishedPurchases() =>
      _dataSource.knownUnfinishedPurchases;

  @override
  Future<Either<Failure, Unit>> completePurchase(StorePurchase purchase) async {
    try {
      await _dataSource.completePurchase(purchase);
      return const Right(unit);
    } catch (e) {
      return Left(StorePurchaseFailure(e.toString()));
    }
  }
}
