import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../../domain/repositories/paywall_repository.dart';
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
  Future<Either<Failure, bool>> isUnlocked() async {
    try {
      final token = await _localDataSource.readUnlockToken();
      if (token == null) return const Right(false);

      final unlocked = await _remoteDataSource.getStatus(token);
      // Il server dice che non vale più (scaduto, o server riavviato): il
      // token non serve a nulla, meglio non tenerlo.
      if (!unlocked) await _localDataSource.clearUnlockToken();
      return Right(unlocked);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> purchaseUnlock() async {
    try {
      final grant = await _remoteDataSource.purchase();
      await _localDataSource.saveUnlockToken(grant.token, grant.validFor);
      return const Right(unit);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
