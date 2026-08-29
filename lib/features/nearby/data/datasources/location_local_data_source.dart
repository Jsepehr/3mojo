import '/features/nearby/domain/entities/geo_location.dart';

/// Contratto per leggere la posizione dal sensore GPS del telefono.
abstract class LocationLocalDataSource {
  Future<GeoLocation> getCurrentLocation();

  /// Aggiornamenti di posizione continui, non una tantum — usato mentre la
  /// sessione è online. Su Android fa partire anche il foreground service
  /// (con notifica persistente) che tiene il processo vivo con l'app in
  /// background, invece di farsi congelare da Android come un timer normale.
  Stream<GeoLocation> watchPosition();
}
