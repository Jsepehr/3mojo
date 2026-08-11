import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/session/data/datasources/face_detection_local_data_source.dart';
import '/features/session/domain/repositories/face_detection_repository.dart';

/// Passacarte verso il datasource ML Kit, traducendo le eccezioni in `Failure`.
class FaceDetectionRepositoryImpl implements FaceDetectionRepository {
  const FaceDetectionRepositoryImpl(this._localDataSource);

  final FaceDetectionLocalDataSource _localDataSource;

  @override
  Future<Either<Failure, bool>> containsFace(String imagePath) async {
    try {
      return Right(await _localDataSource.detectFace(imagePath));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
