
import '/features/nearby/domain/entities/geo_location.dart';

/// Contratto per leggere la posizione dal sensore GPS del telefono.
abstract class LocationLocalDataSource {
  Future<GeoLocation> getCurrentLocation();
}
