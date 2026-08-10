import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../../domain/entities/encounter_request.dart';
import '../../domain/repositories/encounter_repository.dart';
import '../datasources/encounter_remote_data_source.dart';

class EncounterRepositoryImpl implements EncounterRepository {
  const EncounterRepositoryImpl(this._remoteDataSource);

  final EncounterRemoteDataSource _remoteDataSource;

  @override
  Future<Either<Failure, EncounterRequest>> sendRequest({
    required String otherPersonId,
    required String otherSelfiePath,
  }) async {
    try {
      return Right(
        await _remoteDataSource.sendRequest(
          otherPersonId: otherPersonId,
          otherSelfiePath: otherSelfiePath,
        ),
      );
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<EncounterRequest>>> getIncomingRequests() async {
    try {
      return Right(await _remoteDataSource.getIncomingRequests());
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<EncounterRequest>>> getOutgoingRequests() async {
    try {
      return Right(await _remoteDataSource.getOutgoingRequests());
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, EncounterRequest>> respondToRequest({
    required String requestId,
    required bool accepted,
  }) async {
    try {
      return Right(
        await _remoteDataSource.respondToRequest(
          requestId: requestId,
          accepted: accepted,
        ),
      );
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> cancelOtherPendingRequests(
    String exceptRequestId,
  ) async {
    try {
      await _remoteDataSource.cancelOtherPendingRequests(exceptRequestId);
      return const Right(unit);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> endMatch(String requestId) async {
    try {
      await _remoteDataSource.endMatch(requestId);
      return const Right(unit);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
