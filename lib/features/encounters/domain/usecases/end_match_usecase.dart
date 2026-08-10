import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/encounter_repository.dart';

class EndMatchUseCase implements UseCase<Unit, String> {
  const EndMatchUseCase(this._repository);

  final EncounterRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String requestId) =>
      _repository.endMatch(requestId);
}
