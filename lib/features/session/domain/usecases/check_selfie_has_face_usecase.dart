import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/repositories/face_detection_repository.dart';

/// Azione: verifica che il selfie contenga un volto, prima di accettarlo —
/// è la regola di business che impedisce di mettere un'immagine a caso
/// (un paesaggio, un logo) al posto di un selfie vero.
class CheckSelfieHasFaceUseCase implements UseCase<Unit, String> {
  const CheckSelfieHasFaceUseCase(this._repository);

  final FaceDetectionRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String imagePath) async {
    final result = await _repository.containsFace(imagePath);

    return result.match((failure) => Left(failure), (hasFace) {
      if (!hasFace) {
        return const Left(
          ValidationFailure('Non troviamo un volto in questa foto'),
        );
      }
      return const Right(unit);
    });
  }
}
