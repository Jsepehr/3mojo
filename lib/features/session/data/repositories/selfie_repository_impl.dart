import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/exceptions.dart';
import '/core/errors/failures.dart';
import '/features/session/data/datasources/selfie_local_data_source.dart';
import '/features/session/domain/repositories/selfie_repository.dart';

/// Passacarte verso il datasource del selfie, traducendo le eccezioni in
/// `SelfieCaptureFailure`.
class SelfieRepositoryImpl implements SelfieRepository {
  const SelfieRepositoryImpl(this._localDataSource);

  final SelfieLocalDataSource _localDataSource;

  @override
  Future<Either<Failure, Uint8List?>> takeSelfie() async {
    try {
      return Right(await _localDataSource.takeSelfie());
    } on CacheException catch (e) {
      return Left(SelfieCaptureFailure(e.message));
    } catch (e) {
      return Left(SelfieCaptureFailure(e.runtimeType.toString()));
    }
  }

  @override
  Future<Either<Failure, Uint8List>> flipHorizontally(
    Uint8List selfieBytes,
  ) async {
    try {
      return Right(await _localDataSource.flipHorizontally(selfieBytes));
    } on CacheException catch (e) {
      return Left(SelfieCaptureFailure(e.message));
    } catch (e) {
      return Left(SelfieCaptureFailure(e.runtimeType.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> discardLeftoverFiles() async {
    try {
      await _localDataSource.discardLeftoverFiles();
      return const Right(unit);
    } catch (e) {
      return Left(SelfieCaptureFailure(e.runtimeType.toString()));
    }
  }
}
