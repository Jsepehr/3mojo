import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/encounter_request.dart';
import '../repositories/encounter_repository.dart';

/// Azione: le richieste che altri hanno mandato a te.
class GetIncomingRequestsUseCase
    implements UseCase<List<EncounterRequest>, NoParams> {
  const GetIncomingRequestsUseCase(this._repository);

  final EncounterRepository _repository;

  @override
  Future<Either<Failure, List<EncounterRequest>>> call(NoParams params) =>
      _repository.getIncomingRequests();
}
