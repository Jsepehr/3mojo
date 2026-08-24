import '/features/nearby/data/models/nearby_person_model.dart';

/// Contratto verso il backend `server/` (dart_frog, in esecuzione in
/// locale): manda la mia presenza e chiede chi c'è vicino, o mi toglie
/// dalla vista di tutti quando vado offline.
abstract class NearbyRemoteDataSource {
  /// `POST /presence` (la mia posizione + profilo) seguito da `GET /nearby`
  /// (chi c'è entro `radiusMeters`) — un'unica azione lato client, due
  /// chiamate REST lato server.
  Future<List<NearbyPersonModel>> reportPresenceAndFetchNearbyPeople({
    required String sessionId,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required String gender,
    required String genderPreference,
    required String selfieBase64,
  });

  /// `DELETE /presence` — equivalente del bottone End: chi esce non deve
  /// più comparire nella lista di nessuno.
  Future<void> removePresence(String sessionId);
}
