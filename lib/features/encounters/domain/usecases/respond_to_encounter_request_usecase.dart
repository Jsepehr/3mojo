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
/// regola di business "un solo match alla volta" (un sì cancella ogni
/// altra richiesta pendente, per entrambe le parti) è applicata dal
/// server: qui non c'è più nessun passo separato da orchestrare, arriva
/// già risolta col prossimo snapshot (o rifiutata, es. `inMatch`, vedi
/// `WatchEncounterRejectionsUseCase`).
class RespondToEncounterRequestUseCase {
  const RespondToEncounterRequestUseCase(this._repository);

  final EncounterRepository _repository;

  Either<Failure, Unit> call(RespondToEncounterRequestParams params) =>
      _repository.respondToRequest(
        requestId: params.requestId,
        accepted: params.accepted,
      );
}
