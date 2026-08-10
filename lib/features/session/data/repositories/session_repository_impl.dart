import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/online_session.dart';
import '../../domain/repositories/session_repository.dart';
import '../datasources/session_local_data_source.dart';

class SessionRepositoryImpl implements SessionRepository {
  const SessionRepositoryImpl(this._localDataSource);

  final SessionLocalDataSource _localDataSource;

  @override
  Future<Either<Failure, OnlineSession?>> getCurrentSession() async {
    try {
      return Right(await _localDataSource.getCurrentSession());
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, OnlineSession>> startSession({
    required String selfiePath,
    required Gender gender,
    required GenderPreference genderPreference,
  }) async {
    try {
      final session = await _localDataSource.startSession(
        OnlineSession(
          selfiePath: selfiePath,
          gender: gender,
          genderPreference: genderPreference,
        ),
      );
      return Right(session);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> endSession() async {
    try {
      await _localDataSource.endSession();
      return const Right(unit);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
