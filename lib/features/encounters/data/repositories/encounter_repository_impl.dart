import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '/core/errors/exceptions.dart';
import '/core/errors/failures.dart';
import '../../domain/entities/encounter_rejection.dart';
import '../../domain/entities/encounter_request.dart';
import '../../domain/repositories/encounter_repository.dart';
import '../datasources/encounter_remote_data_source.dart';

/// Passacarte verso il datasource, traducendo gli errori della connessione
/// (`ServerException`) in `ConnectionFailure` e ogni altro errore in
/// `UnexpectedFailure`.
class EncounterRepositoryImpl implements EncounterRepository {
  const EncounterRepositoryImpl(this._remoteDataSource);

  final EncounterRemoteDataSource _remoteDataSource;

  @override
  Stream<
    Either<
      Failure,
      ({List<EncounterRequest> incoming, List<EncounterRequest> outgoing})
    >
  >
  watchRequests(String sessionId) {
    return _remoteDataSource
        .watchRequests(sessionId)
        .transform(
          StreamTransformer<
            EncounterSnapshotModel,
            Either<
              Failure,
              ({
                List<EncounterRequest> incoming,
                List<EncounterRequest> outgoing,
              })
            >
          >.fromHandlers(
            handleData: (snapshot, sink) => sink.add(Right(snapshot)),
            handleError: (error, stackTrace, sink) =>
                sink.add(Left(_failureFor(error))),
          ),
        );
  }

  @override
  Stream<EncounterRejection> watchRejections(String sessionId) =>
      _remoteDataSource.watchRejections(sessionId).handleError((Object _) {});

  @override
  Either<Failure, Unit> sendRequest({required String otherPersonId}) =>
      _attempt(
        () => _remoteDataSource.sendRequest(otherPersonId: otherPersonId),
      );

  @override
  Either<Failure, Unit> respondToRequest({
    required String requestId,
    required bool accepted,
  }) => _attempt(
    () => _remoteDataSource.respondToRequest(
      requestId: requestId,
      accepted: accepted,
    ),
  );

  @override
  Either<Failure, Unit> endMatch(String requestId) =>
      _attempt(() => _remoteDataSource.endMatch(requestId));

  @override
  Future<Either<Failure, Unit>> clearSessionState() async {
    try {
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
