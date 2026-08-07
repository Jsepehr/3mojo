import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/geo_location.dart';

abstract class LocationRepository {
  Future<Either<Failure, GeoLocation>> getCurrentLocation();
}
