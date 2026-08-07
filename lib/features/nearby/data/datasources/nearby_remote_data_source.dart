import '../models/nearby_person_model.dart';

abstract class NearbyRemoteDataSource {
  Future<List<NearbyPersonModel>> fetchNearbyPeople();
}
