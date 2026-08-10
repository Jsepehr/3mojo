import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/encounter_request.dart';

abstract class EncounterRepository {
  Future<Either<Failure, EncounterRequest>> sendRequest({
    required String otherPersonId,
    required String otherSelfiePath,
  });

  Future<Either<Failure, List<EncounterRequest>>> getIncomingRequests();

  Future<Either<Failure, List<EncounterRequest>>> getOutgoingRequests();

  Future<Either<Failure, EncounterRequest>> respondToRequest({
    required String requestId,
    required bool accepted,
  });

  Future<Either<Failure, Unit>> cancelOtherPendingRequests(
    String exceptRequestId,
  );

  Future<Either<Failure, Unit>> endMatch(String requestId);
}
