import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/session/domain/usecases/session_teardown_usecase.dart';
import '../repositories/encounter_repository.dart';

/// Azione: dimentica le richieste della sessione appena finita. È uno dei
/// passi di pulizia di End (`EndSessionUseCase`, tramite il contratto
/// [SessionTeardownUseCase]): le richieste di ieri non devono comparire in
/// una sessione nuova.
class ClearEncounterSessionStateUseCase implements SessionTeardownUseCase {
  const ClearEncounterSessionStateUseCase(this._repository);

  final EncounterRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String endingSessionId) =>
      _repository.clearSessionState();
}
