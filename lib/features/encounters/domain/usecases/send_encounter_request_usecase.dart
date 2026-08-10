import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/encounter_request.dart';
import '../repositories/encounter_repository.dart';

class SendEncounterRequestParams extends Equatable {
  const SendEncounterRequestParams({
    required this.otherPersonId,
    required this.otherSelfiePath,
  });

  final String otherPersonId;
  final String otherSelfiePath;

  @override
  List<Object?> get props => [otherPersonId, otherSelfiePath];
}

class SendEncounterRequestUseCase
    implements UseCase<EncounterRequest, SendEncounterRequestParams> {
  const SendEncounterRequestUseCase(this._repository);

  final EncounterRepository _repository;

  @override
  Future<Either<Failure, EncounterRequest>> call(
    SendEncounterRequestParams params,
  ) => _repository.sendRequest(
    otherPersonId: params.otherPersonId,
    otherSelfiePath: params.otherSelfiePath,
  );
}
