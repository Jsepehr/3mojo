import 'package:fpdart/fpdart.dart';

import '/core/errors/exceptions.dart';
import '/core/errors/failures.dart';
import '../../domain/entities/store_purchase.dart';
import '../../domain/repositories/paywall_repository.dart';
import '../models/store_purchase_model.dart';
import '../datasources/paywall_local_data_source.dart';
import '../datasources/paywall_remote_data_source.dart';

/// Orchestra i due datasource: il token di sblocco locale (esiste solo se
/// si è pagato, e solo finché vale) e la chiamata al server (l'unica
/// autorità su quanto dura lo sblocco). Senza token non c'è nulla da
/// chiedere: chi non paga non contatta mai il paywall e non si identifica
/// in nessun modo.
class PaywallRepositoryImpl implements PaywallRepository {
  const PaywallRepositoryImpl(this._localDataSource, this._remoteDataSource);

  final PaywallLocalDataSource _localDataSource;
  final PaywallRemoteDataSource _remoteDataSource;

  @override
  Future<Either<Failure, Duration>> getUnlockTimeRemaining() async {
    try {
      final token = await _localDataSource.readUnlockToken();
      if (token == null) return const Right(Duration.zero);

      final remaining = await _remoteDataSource.getRemaining(token);
      // Il server dice che non vale più (scaduto, o server riavviato): il
      // token non serve a nulla, meglio non tenerlo. Toglierlo avvisa anche
      // `nearby/`, che rimanda la presenza senza: il server ricalcola subito
      // chi è bloccato.
      if (remaining <= Duration.zero) {
        await _localDataSource.clearUnlockToken();
        return const Right(Duration.zero);
      }
      return Right(remaining);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Duration>> redeemPurchase(
    StorePurchase purchase,
  ) async {
    try {
      final grant = await _remoteDataSource.redeemPurchase(
        StorePurchaseModel.fromEntity(purchase),
      );
      await _localDataSource.saveUnlockToken(grant.token, grant.remaining);
      return Right(grant.remaining);
    } on PurchaseRejectedException catch (e) {
      return Left(PurchaseNotVerifiedFailure(e.code));
    } on PurchaseAlreadyRedeemedException {
      return const Left(PurchaseAlreadyRedeemedFailure());
    } on ServerException catch (e) {
      return Left(ConnectionFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
