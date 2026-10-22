import 'package:fpdart/fpdart.dart';

import '/core/errors/exceptions.dart';
import '/core/errors/failures.dart';
import '../../domain/entities/report_reason.dart';
import '../../domain/entities/safety_rejection.dart';
import '../../domain/repositories/safety_repository.dart';
import '../datasources/blocked_people_local_data_source.dart';
import '../datasources/safety_remote_data_source.dart';

/// Manda blocchi e segnalazioni al server e, **solo se sono partiti**,
/// segna la persona tra i bloccati della sessione (così sparisce subito) e
/// conta la segnalazione. Traduce `ServerException` in `ConnectionFailure`
/// e ogni altro errore in `UnexpectedFailure`.
class SafetyRepositoryImpl implements SafetyRepository {
  const SafetyRepositoryImpl(this._remoteDataSource, this._localDataSource);

  final SafetyRemoteDataSource _remoteDataSource;
  final BlockedPeopleLocalDataSource _localDataSource;

  @override
  Either<Failure, Unit> blockPerson(String personId) => _attempt(() {
    _remoteDataSource.block(personId);
    _localDataSource.addBlocked(personId);
  });

  @override
  Either<Failure, Unit> reportPerson({
    required String personId,
    required ReportReason reason,
  }) => _attempt(() {
    _remoteDataSource.report(personId: personId, reason: reason);
    _localDataSource
      ..addBlocked(personId)
      ..incrementReportsSent();
  });

  @override
  int get reportsSentThisSession => _localDataSource.reportsSent;

  @override
  Stream<Set<String>> watchBlockedPersonIds() =>
      _localDataSource.watchBlockedPersonIds();

  @override
  Stream<SafetyRejection> watchRejections(String sessionId) =>
      _remoteDataSource.watchRejections(sessionId).handleError((Object _) {});

  @override
  Future<Either<Failure, Unit>> clearSessionState() async {
    try {
      _localDataSource.clear();
      await _remoteDataSource.reset();
      return const Right(unit);
    } catch (e) {
      return Left(_failureFor(e));
    }
  }

  Either<Failure, Unit> _attempt(void Function() action) {
    try {
      action();
      return const Right(unit);
    } catch (e) {
      return Left(_failureFor(e));
    }
  }

  static Failure _failureFor(Object error) => error is ServerException
      ? ConnectionFailure(error.message)
      : UnexpectedFailure(error.toString());
}
