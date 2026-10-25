import '/features/nearby/domain/entities/background_location_notice.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import '/features/nearby/domain/entities/location_permission_status.dart';
import 'location_local_data_source.dart';

/// Implementazione **finta** del GPS, per la demo dichiarata (`DemoScope`):
/// nessun sensore, nessun permesso chiesto né letto, nessun foreground
/// service. Una posizione fissa e senza significato (0, 0), che non esce mai
/// dal telefono: nella demo anche "Vicinanze" è finta
/// (`NearbyRemoteDataSourceFakeImpl`) e ignora la posizione.
class LocationLocalDataSourceFakeImpl implements LocationLocalDataSource {
  static const _fixedLocation = GeoLocation(latitude: 0, longitude: 0);

  @override
  Future<GeoLocation> getCurrentLocation() async => _fixedLocation;

  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      LocationPermissionStatus.granted;

  @override
  bool get keepsTrackingInBackground => false;

  @override
  Stream<GeoLocation> watchPosition({
    required BackgroundLocationNotice notice,
  }) => const Stream.empty();

  @override
  Future<bool> openLocationSettings() async => false;

  @override
  Future<bool> openAppSettings() async => false;
}
