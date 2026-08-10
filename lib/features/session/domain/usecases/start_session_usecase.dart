import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/repositories/session_repository.dart';

class StartSessionParams extends Equatable {
  const StartSessionParams({
    required this.selfiePath,
    required this.gender,
    required this.genderPreference,
  });

  final String selfiePath;
  final Gender gender;
  final GenderPreference genderPreference;

  @override
  List<Object?> get props => [selfiePath, gender, genderPreference];
}

/// Azione: vai online. Valida che ci sia un selfie prima di salvare la
/// sessione — è la regola di business, non un dettaglio della UI.
class StartSessionUseCase
    implements UseCase<OnlineSession, StartSessionParams> {
  const StartSessionUseCase(this._repository);

  final SessionRepository _repository;

  @override
  Future<Either<Failure, OnlineSession>> call(StartSessionParams params) async {
    if (params.selfiePath.isEmpty) {
      return const Left(ValidationFailure('Serve un selfie per andare online'));
    }

    return _repository.startSession(
      selfiePath: params.selfiePath,
      gender: params.gender,
      genderPreference: params.genderPreference,
    );
  }
}
