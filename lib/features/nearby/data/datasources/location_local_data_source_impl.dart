import 'package:geolocator/geolocator.dart';

import '/core/errors/exceptions.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import 'location_local_data_source.dart';

/// Implementazione **reale**: usa il pacchetto `geolocator` per controllare
/// permessi/GPS attivo e leggere la posizione vera del telefono.
class LocationLocalDataSourceImpl implements LocationLocalDataSource {
  @override
  Future<GeoLocation> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationDisabledException(
        'Il servizio di localizzazione è disattivato',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDeniedException(
        'Permesso di localizzazione negato',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    return GeoLocation(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
