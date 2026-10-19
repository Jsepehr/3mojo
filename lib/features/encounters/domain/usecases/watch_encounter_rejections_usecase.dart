import '/core/usecases/usecase.dart';
import '/features/session/domain/usecases/get_current_session_usecase.dart';
import '../entities/encounter_rejection.dart';
import '../repositories/encounter_repository.dart';

/// Azione: resta in ascolto delle azioni (richieste, risposte) che il
/// server ha rifiutato, col motivo — per dirlo all'utente invece di
/// lasciargli credere che siano andate a buon fine. Senza sessione non
/// emette nulla.
class WatchEncounterRejectionsUseCase {
  const WatchEncounterRejectionsUseCase({
    required GetCurrentSessionUseCase getCurrentSessionUseCase,
    required EncounterRepository repository,
  }) : _getCurrentSessionUseCase = getCurrentSessionUseCase,
       _repository = repository;

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final EncounterRepository _repository;

  Stream<EncounterRejection> call() async* {
    final sessionResult = await _getCurrentSessionUseCase(const NoParams());
    final sessionId = sessionResult.match(
      (_) => null,
      (session) => session?.sessionId,
    );
    if (sessionId == null) return;

    yield* _repository.watchRejections(sessionId);
  }
}
