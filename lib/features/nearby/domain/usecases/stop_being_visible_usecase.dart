import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/nearby/domain/repositories/nearby_repository.dart';
import '/features/session/domain/usecases/session_teardown_usecase.dart';

/// Azione: smetti di comparire nella lista "Vicinanze" di chiunque altro —
/// equivalente del bottone End, lato server. È uno dei passi di pulizia
/// che `EndSessionUseCase` (feature `session`) compone a End, tramite il
/// contratto [SessionTeardownUseCase]: così `session/` non dipende da
/// `nearby/` (la dipendenza va solo da qui verso là). L'id della sessione
/// che il contratto passa non serve: c'è una sola connessione, quella in
/// corso.
class StopBeingVisibleUseCase implements SessionTeardownUseCase {
  const StopBeingVisibleUseCase(this._repository);

  final NearbyRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String sessionId) =>
      _repository.stopBeingVisible();
}
