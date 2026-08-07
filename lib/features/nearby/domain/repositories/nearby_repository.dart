import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/geo_location.dart';
import '../entities/nearby_person.dart';

abstract class NearbyRepository {
  Future<Either<Failure, List<NearbyPerson>>> getNearbyPeople(
    GeoLocation location, {
    required double radiusMeters,
  });
}
