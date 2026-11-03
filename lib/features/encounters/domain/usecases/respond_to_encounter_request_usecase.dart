import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
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

/// Azione: rispondi sì/no a una richiesta in arrivo. `Right` = la risposta
/// è partita, `Left(ConnectionFailure)` = non è partita (offline). La
/// regola di business "un solo match alla volta" è applicata dal server:
/// un sì cambia solo lo stato di quella richiesta (le altre pendenti
/// restano pendenti) ed è rifiutato (`inMatch`, vedi
/// `WatchEncounterRejectionsUseCase`) se una delle due parti è già in un
/// match; il no è sempre possibile. Qui non c'è nessun passo separato da
/// orchestrare.
class RespondToEncounterRequestUseCase {
  const RespondToEncounterRequestUseCase(this._repository);

  final EncounterRepository _repository;

  Either<Failure, Unit> call(RespondToEncounterRequestParams params) =>
      _repository.respondToRequest(
        requestId: params.requestId,
        accepted: params.accepted,
      );
}
