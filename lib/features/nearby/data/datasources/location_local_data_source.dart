import '/features/nearby/domain/entities/background_location_notice.dart';
import '/features/nearby/domain/entities/geo_location.dart';

/// Contratto per leggere la posizione dal sensore GPS del telefono.
abstract class LocationLocalDataSource {
  Future<GeoLocation> getCurrentLocation();

  /// Aggiornamenti di posizione continui, non una tantum — usato mentre la
  /// sessione è online. Su Android fa partire anche il foreground service
  /// (con notifica persistente) che tiene il processo vivo con l'app in
  /// background, invece di farsi congelare da Android come un timer normale.
  /// [notice] sono i testi (tradotti, dagli ARB) di quella notifica:
  /// obbligatori, il data layer non ha testi propri.
  Stream<GeoLocation> watchPosition({required BackgroundLocationNotice notice});

  /// Apre le impostazioni di sistema della localizzazione (per riaccendere
  /// il GPS). `false` se il sistema non ha potuto aprirle.
  Future<bool> openLocationSettings();

  /// Apre la pagina di questa app nelle impostazioni di sistema (per
  /// concedere di nuovo un permesso negato "per sempre").
  Future<bool> openAppSettings();
}
