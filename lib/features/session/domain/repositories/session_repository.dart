import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/online_session.dart';

abstract class SessionRepository {
  Future<Either<Failure, OnlineSession?>> getCurrentSession();

  Future<Either<Failure, OnlineSession>> startSession({
    required String selfiePath,
    required Gender gender,
    required GenderPreference genderPreference,
  });

  Future<Either<Failure, Unit>> endSession();
}
