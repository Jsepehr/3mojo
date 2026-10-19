import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/profile_repository.dart';

/// Azione: cancella il profilo dal telefono — è anche il modo di ritirare
/// il consenso al dato sensibile. Al prossimo avvio il profilo va
/// ricompilato da zero.
class DeleteProfileUseCase implements UseCase<Unit, NoParams> {
  const DeleteProfileUseCase(this._repository);

  final ProfileRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) =>
      _repository.deleteProfile();
}
