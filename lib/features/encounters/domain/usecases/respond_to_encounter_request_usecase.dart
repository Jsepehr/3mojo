import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/encounter_request.dart';
import '../repositories/encounter_repository.dart';

class RespondToEncounterRequestParams extends Equatable {
  const RespondToEncounterRequestParams({
    required this.requestId,
    required this.accepted,
  });

  final String requestId;
  final bool accepted;

  @override
  List<Object?> get props => [requestId, accepted];
}

/// Azione: rispondi sì/no a una richiesta in arrivo. Un sì innesca la
/// regola di business "un solo match alla volta": cancella tutte le altre
/// richieste pendenti (viste sopra, `cancelOtherPendingRequests`).
class RespondToEncounterRequestUseCase
    implements UseCase<EncounterRequest, RespondToEncounterRequestParams> {
  const RespondToEncounterRequestUseCase(this._repository);

  final EncounterRepository _repository;

  @override
  Future<Either<Failure, EncounterRequest>> call(
    RespondToEncounterRequestParams params,
  ) async {
    final result = await _repository.respondToRequest(
      requestId: params.requestId,
      accepted: params.accepted,
    );

    // Accepting one request commits to a single encounter: every other
    // pending request (incoming or outgoing) is cancelled to make room.
    if (params.accepted && result.isRight()) {
      await _repository.cancelOtherPendingRequests(params.requestId);
    }

    return result;
  }
}
