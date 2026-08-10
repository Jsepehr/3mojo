import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/geo_location.dart';
import '../entities/nearby_person.dart';

/// Contratto per ottenere le persone entro un certo raggio da una posizione.
/// L'implementazione reale interrogherebbe un backend; qui è finta.
abstract class NearbyRepository {
  Future<Either<Failure, List<NearbyPerson>>> getNearbyPeople(
    GeoLocation location, {
    required double radiusMeters,
  });
}
