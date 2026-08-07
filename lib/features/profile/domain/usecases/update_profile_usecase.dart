import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/profile.dart';
import '../repositories/profile_repository.dart';

class UpdateProfileUseCase implements UseCase<Profile, Profile> {
  const UpdateProfileUseCase(this._repository);

  final ProfileRepository _repository;

  @override
  Future<Either<Failure, Profile>> call(Profile params) async {
    final name = params.name.trim();

    if (name.isEmpty) {
      return const Left(ValidationFailure('Il nome non può essere vuoto'));
    }
    if (params.age < 18) {
      return const Left(ValidationFailure('Devi avere almeno 18 anni'));
    }

    return _repository.updateProfile(params.copyWith(name: name));
  }
}
