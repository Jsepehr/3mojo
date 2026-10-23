import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '/core/errors/exceptions.dart';
import '/features/nearby/domain/entities/background_location_notice.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import '/features/nearby/domain/entities/location_permission_status.dart';
import 'location_local_data_source.dart';

/// Implementazione **reale**: usa il pacchetto `geolocator` per controllare
/// permessi/GPS attivo e leggere la posizione vera del telefono.
class LocationLocalDataSourceImpl implements LocationLocalDataSource {
  @override
  Future<GeoLocation> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationDisabledException('Location services are disabled');
    }

    // Solo controllo, mai la richiesta: quella parte da [requestPermission]
    // dopo l'avviso in evidenza. Chiederla qui la mostrerebbe senza avviso
    // (anche a ogni nuovo tentativo di `ProNearby`, se il permesso viene
    // tolto a sessione aperta).
    if (await checkPermission() != LocationPermissionStatus.granted) {
      throw const LocationPermissionDeniedException(
        'Location permission denied',
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
  Future<LocationPermissionStatus> checkPermission() async =>
      _statusOf(await Geolocator.checkPermission());

  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      _statusOf(await Geolocator.requestPermission());

  @override
  bool get keepsTrackingInBackground =>
      defaultTargetPlatform == TargetPlatform.android;

  static LocationPermissionStatus _statusOf(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.whileInUse ||
        LocationPermission.always => LocationPermissionStatus.granted,
        LocationPermission.deniedForever =>
          LocationPermissionStatus.deniedForever,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine => LocationPermissionStatus.denied,
      };

  @override
  Stream<GeoLocation> watchPosition({
    required BackgroundLocationNotice notice,
  }) async* {
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
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: notice.title,
              notificationText: notice.body,
              notificationChannelName: notice.channelName,
              enableWakeLock: true,
            ),
          )
        : const LocationSettings(distanceFilter: 0);

    yield* Geolocator.getPositionStream(locationSettings: settings).map(
      (position) => GeoLocation(
        latitude: position.latitude,
        longitude: position.longitude,
      ),
    );
  }

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
