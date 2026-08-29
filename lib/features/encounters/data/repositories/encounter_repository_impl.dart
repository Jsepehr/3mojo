import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../../domain/entities/encounter_request.dart';
import '../../domain/repositories/encounter_repository.dart';
import '../datasources/encounter_remote_data_source.dart';
import '../models/encounter_request_model.dart';

/// Passacarte verso il datasource reale, traducendo eventuali errori della
/// connessione in `Failure`.
class EncounterRepositoryImpl implements EncounterRepository {
  const EncounterRepositoryImpl(this._remoteDataSource);

  final EncounterRemoteDataSource _remoteDataSource;

  @override
  Stream<Either<Failure, ({List<EncounterRequest> incoming, List<EncounterRequest> outgoing})>>
  watchRequests(String sessionId) {
    return _remoteDataSource
        .watchRequests(sessionId)
        .transform(
          StreamTransformer<
            ({
              List<EncounterRequestModel> incoming,
              List<EncounterRequestModel> outgoing,
            }),
            Either<
              Failure,
              ({List<EncounterRequest> incoming, List<EncounterRequest> outgoing})
            >
          >.fromHandlers(
            handleData: (snapshot, sink) => sink.add(Right(snapshot)),
            handleError: (error, stackTrace, sink) =>
                sink.add(Left(UnexpectedFailure(error.toString()))),
          ),
        );
  }

  @override
  void sendRequest({required String otherPersonId}) {
    _remoteDataSource.sendRequest(otherPersonId: otherPersonId);
  }

  @override
  void respondToRequest({required String requestId, required bool accepted}) {
    _remoteDataSource.respondToRequest(requestId: requestId, accepted: accepted);
  }

  @override
  void endMatch(String requestId) {
    _remoteDataSource.endMatch(requestId);
  }
}
