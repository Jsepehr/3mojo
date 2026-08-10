import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/encounter_request.dart';
import '../repositories/encounter_repository.dart';

class GetOutgoingRequestsUseCase
    implements UseCase<List<EncounterRequest>, NoParams> {
  const GetOutgoingRequestsUseCase(this._repository);

  final EncounterRepository _repository;

  @override
  Future<Either<Failure, List<EncounterRequest>>> call(NoParams params) =>
      _repository.getOutgoingRequests();
}
