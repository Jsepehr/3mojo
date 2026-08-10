import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/session_repository.dart';

/// Azione: vai offline. Azzera la sessione, si ricomincia da Start.
class EndSessionUseCase implements UseCase<Unit, NoParams> {
  const EndSessionUseCase(this._repository);

  final SessionRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) =>
      _repository.endSession();
}
