import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/online_session.dart';
import '../repositories/session_repository.dart';

class GetCurrentSessionUseCase implements UseCase<OnlineSession?, NoParams> {
  const GetCurrentSessionUseCase(this._repository);

  final SessionRepository _repository;

  @override
  Future<Either<Failure, OnlineSession?>> call(NoParams params) =>
      _repository.getCurrentSession();
}
