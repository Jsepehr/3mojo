import '../models/encounter_request_model.dart';

/// Contratto per lo scambio di richieste d'interesse con un backend.
abstract class EncounterRemoteDataSource {
  Future<EncounterRequestModel> sendRequest({
    required String otherPersonId,
    required String otherSelfiePath,
  });

  Future<List<EncounterRequestModel>> getIncomingRequests();

  Future<List<EncounterRequestModel>> getOutgoingRequests();

  Future<EncounterRequestModel> respondToRequest({
    required String requestId,
    required bool accepted,
  });

  Future<void> cancelOtherPendingRequests(String exceptRequestId);

  Future<void> endMatch(String requestId);
}
