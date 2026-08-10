import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/geo_location.dart';

/// Contratto per leggere la posizione GPS reale del proprio telefono.
abstract class LocationRepository {
  Future<Either<Failure, GeoLocation>> getCurrentLocation();
}
