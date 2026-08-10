import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/repositories/session_repository.dart';

/// Azione: c'è già una sessione online in corso? (null se sei offline).
class GetCurrentSessionUseCase implements UseCase<OnlineSession?, NoParams> {
  const GetCurrentSessionUseCase(this._repository);

  final SessionRepository _repository;

  @override
  Future<Either<Failure, OnlineSession?>> call(NoParams params) =>
      _repository.getCurrentSession();
}
