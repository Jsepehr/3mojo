import 'package:fpdart/fpdart.dart';

import '/core/errors/exceptions.dart';
import '/core/errors/failures.dart';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_local_data_source.dart';
import '../models/profile_model.dart';

/// Passacarte verso il datasource locale, traducendo le eccezioni in `Failure`.
class ProfileRepositoryImpl implements ProfileRepository {
  const ProfileRepositoryImpl(this._localDataSource);

  final ProfileLocalDataSource _localDataSource;

  @override
  Future<Either<Failure, Profile?>> getProfile() =>
      _guard(_localDataSource.getProfile);

  @override
  Future<Either<Failure, Unit>> saveProfile(Profile profile) =>
      _guard(() async {
        await _localDataSource.saveProfile(ProfileModel.fromEntity(profile));
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> deleteProfile() => _guard(() async {
    await _localDataSource.deleteProfile();
    return unit;
  });

  @override
  Future<Either<Failure, bool>> isFirstLaunchAfterInstall() =>
      _guard(() async => !await _localDataSource.hasInstallMarker());

  @override
  Future<Either<Failure, Unit>> markFirstLaunchDone() => _guard(() async {
    await _localDataSource.setInstallMarker();
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> deleteAllSecureData() => _guard(() async {
    await _localDataSource.deleteAllSecureData();
    return unit;
  });

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Right(await action());
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    }
  }
}
