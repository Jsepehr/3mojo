import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

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

  @override
  Stream<GeoLocation> watchPosition() async* {
    // Il foreground service (con notifica persistente) è un concetto solo
    // Android — su altre piattaforme resta un normale stream di posizione.
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Da Android 13 (API 33) senza questo permesso la notifica del
      // foreground service resta invisibile — il tracking parte comunque,
      // ma l'utente non lo vedrebbe mai succedere. Best-effort: se nega,
      // si va avanti lo stesso.
      await Permission.notification.request();
    }

    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            intervalDuration: const Duration(seconds: 60),
            distanceFilter: 0,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: '3mojo è online',
              notificationText:
                  'Stai comparendo a chi ti è vicino, anche con l\'app '
                  'in background.',
              notificationChannelName: 'Presenza online',
              enableWakeLock: true,
            ),
          )
        : const LocationSettings(distanceFilter: 0);

    yield* Geolocator.getPositionStream(locationSettings: settings).map(
      (position) =>
          GeoLocation(latitude: position.latitude, longitude: position.longitude),
    );
  }
}
