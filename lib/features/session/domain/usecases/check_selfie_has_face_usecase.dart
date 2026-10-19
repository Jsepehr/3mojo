import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/repositories/face_detection_repository.dart';

/// Azione: verifica che il selfie contenga un volto, prima di accettarlo —
/// è la regola di business che impedisce di mettere un'immagine a caso
/// (un paesaggio, un logo) al posto di un selfie vero.
///
/// Errori: `SelfieMissingFailure` (nessun selfie), `NoFaceInSelfieFailure`
/// (nessun volto), `FaceCheckUnavailableFailure` (il controllo non è
/// riuscito a girare).
class CheckSelfieHasFaceUseCase implements UseCase<Unit, Uint8List> {
  const CheckSelfieHasFaceUseCase(this._repository);

  final FaceDetectionRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(Uint8List selfieBytes) async {
    if (selfieBytes.isEmpty) return const Left(SelfieMissingFailure());

    final result = await _repository.containsFace(selfieBytes);
    return result.flatMap(
      (hasFace) =>
          hasFace ? const Right(unit) : const Left(NoFaceInSelfieFailure()),
    );
  }
}
