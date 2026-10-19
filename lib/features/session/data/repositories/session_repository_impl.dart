import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/profile/domain/entities/profile.dart';
import '/features/session/data/datasources/session_local_data_source.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/repositories/session_repository.dart';

/// Passacarte verso il datasource locale, traducendo le eccezioni in `Failure`.
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
    required String sessionId,
    required Uint8List selfieBytes,
    required Profile profile,
    MeetIntent? intent,
  }) async {
    try {
      final session = await _localDataSource.startSession(
        OnlineSession(
          sessionId: sessionId,
          selfieBytes: selfieBytes,
          profile: profile,
          intent: intent,
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

  @override
  Stream<OnlineSession?> watchSession() => _localDataSource.watchSession();
}
