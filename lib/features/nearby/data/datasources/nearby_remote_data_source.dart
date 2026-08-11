import '/features/nearby/data/models/nearby_person_model.dart';

/// Contratto per ottenere l'elenco di persone vicine da un backend.
abstract class NearbyRemoteDataSource {
  Future<List<NearbyPersonModel>> fetchNearbyPeople();
}
