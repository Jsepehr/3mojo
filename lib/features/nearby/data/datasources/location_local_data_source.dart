import '../../domain/entities/geo_location.dart';

abstract class LocationLocalDataSource {
  Future<GeoLocation> getCurrentLocation();
}
