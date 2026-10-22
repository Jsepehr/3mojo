import '/core/usecases/usecase.dart';
import '/features/session/domain/usecases/get_current_session_usecase.dart';
import '../entities/safety_rejection.dart';
import '../repositories/safety_repository.dart';

/// Azione: i blocchi e le segnalazioni che il server ha rifiutato in
/// questa sessione (persona già uscita, troppe segnalazioni…), per dirlo
/// all'utente invece di lasciargli credere il contrario. Compone
/// `GetCurrentSessionUseCase` per sapere chi sono; senza sessione non
/// emette nulla.
class WatchSafetyRejectionsUseCase {
  const WatchSafetyRejectionsUseCase({
    required GetCurrentSessionUseCase getCurrentSessionUseCase,
    required SafetyRepository repository,
  }) : _getCurrentSessionUseCase = getCurrentSessionUseCase,
       _repository = repository;

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final SafetyRepository _repository;

  Stream<SafetyRejection> call() async* {
    final result = await _getCurrentSessionUseCase(const NoParams());
    final sessionId = result.match((_) => null, (s) => s?.sessionId);
    if (sessionId == null) return;
    yield* _repository.watchRejections(sessionId);
  }
}
