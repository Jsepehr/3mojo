import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/session/domain/usecases/session_teardown_usecase.dart';
import '../repositories/safety_repository.dart';

/// Azione: dimentica bloccati e segnalazioni della sessione appena finita —
/// uno dei passi di End (`EndSessionUseCase`, tramite il contratto
/// [SessionTeardownUseCase]). Gli pseudonimi di una sessione non valgono
/// nella successiva, e il blocco (lato server) finisce con la sessione.
class ClearSafetySessionStateUseCase implements SessionTeardownUseCase {
  const ClearSafetySessionStateUseCase(this._repository);

  final SafetyRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String endingSessionId) =>
      _repository.clearSessionState();
}
