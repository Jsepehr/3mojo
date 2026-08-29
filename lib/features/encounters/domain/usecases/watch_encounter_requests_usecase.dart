import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/usecases/get_current_session_usecase.dart';
import '../entities/encounter_request.dart';
import '../repositories/encounter_repository.dart';

/// Azione: resta in ascolto delle richieste d'incontro in entrata/uscita
/// che ti riguardano — spinte dal server ogni volta che cambia qualcosa
/// (nuova richiesta, risposta, match, esclusività applicata), non
/// richieste a intervalli. Compone `GetCurrentSessionUseCase` per sapere
/// chi sono, come `WatchNearbyPeopleUseCase`.
class WatchEncounterRequestsUseCase {
  const WatchEncounterRequestsUseCase({
    required GetCurrentSessionUseCase getCurrentSessionUseCase,
    required EncounterRepository repository,
  }) : _getCurrentSessionUseCase = getCurrentSessionUseCase,
       _repository = repository;

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final EncounterRepository _repository;

  Stream<Either<Failure, ({List<EncounterRequest> incoming, List<EncounterRequest> outgoing})>>
  call() async* {
    final sessionResult = await _getCurrentSessionUseCase(const NoParams());

    Failure? failure;
    var sessionId = sessionResult.match((f) {
      failure = f;
      return null;
    }, (session) => session?.sessionId);

    if (failure != null) {
      yield Left(failure!);
      return;
    }
    if (sessionId == null) {
      yield const Left(
        ValidationFailure('Devi essere online per vedere le richieste'),
      );
      return;
    }

    yield* _repository.watchRequests(sessionId);
  }
}
