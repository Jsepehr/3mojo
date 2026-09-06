import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../../domain/repositories/paywall_repository.dart';
import '../datasources/paywall_local_data_source.dart';
import '../datasources/paywall_remote_data_source.dart';

/// Orchestra i due datasource: il `deviceId` locale (chi sono, anonimo) e
/// la chiamata al server (l'unica autorità su quanto dura lo sblocco).
class PaywallRepositoryImpl implements PaywallRepository {
  const PaywallRepositoryImpl(this._localDataSource, this._remoteDataSource);

  final PaywallLocalDataSource _localDataSource;
  final PaywallRemoteDataSource _remoteDataSource;

  @override
  Future<Either<Failure, bool>> isUnlocked() async {
    try {
      final deviceId = await _localDataSource.getOrCreateDeviceId();
      final unlocked = await _remoteDataSource.getStatus(deviceId);
      return Right(unlocked);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> purchaseUnlock() async {
    try {
      final deviceId = await _localDataSource.getOrCreateDeviceId();
      await _remoteDataSource.purchase(deviceId);
      return const Right(unit);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
