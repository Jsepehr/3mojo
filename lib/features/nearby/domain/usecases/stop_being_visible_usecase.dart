import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/nearby/domain/repositories/nearby_repository.dart';

/// Azione: smetti di comparire nella lista "Vicinanze" di chiunque altro —
/// equivalente del bottone End, lato server.
class StopBeingVisibleUseCase implements UseCase<Unit, String> {
  const StopBeingVisibleUseCase(this._repository);

  final NearbyRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String sessionId) =>
      _repository.stopBeingVisible(sessionId);
}
