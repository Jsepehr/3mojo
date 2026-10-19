import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/session/data/datasources/face_detection_local_data_source.dart';
import '/features/session/domain/repositories/face_detection_repository.dart';

/// Passacarte verso il datasource di rilevamento volto. Qualsiasi errore
/// tecnico (canale nativo assente o in errore — un `PlatformException` —,
/// file temporaneo non scrivibile) diventa `FaceCheckUnavailableFailure`:
/// la UI dice "non riusciamo a controllare la foto", mai l'eccezione grezza.
class FaceDetectionRepositoryImpl implements FaceDetectionRepository {
  const FaceDetectionRepositoryImpl(this._localDataSource);

  final FaceDetectionLocalDataSource _localDataSource;

  @override
  Future<Either<Failure, bool>> containsFace(Uint8List imageBytes) async {
    try {
      return Right(await _localDataSource.detectFace(imageBytes));
    } catch (e) {
      return Left(FaceCheckUnavailableFailure(e.runtimeType.toString()));
    }
  }
}
