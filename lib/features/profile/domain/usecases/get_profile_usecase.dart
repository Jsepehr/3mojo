import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/profile.dart';
import '../repositories/profile_repository.dart';

/// Azione: leggi il profilo salvato sul telefono (`null` se non c'è ancora).
class GetProfileUseCase implements UseCase<Profile?, NoParams> {
  const GetProfileUseCase(this._repository);

  final ProfileRepository _repository;

  @override
  Future<Either<Failure, Profile?>> call(NoParams params) =>
      _repository.getProfile();
}
