import '/features/nearby/domain/entities/background_location_notice.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import '/features/nearby/domain/entities/location_permission_status.dart';

/// Contratto per leggere la posizione dal sensore GPS del telefono.
abstract class LocationLocalDataSource {
  /// La posizione attuale. **Non** chiede mai il permesso: se manca lancia
  /// `LocationPermissionDeniedException` — la richiesta parte solo da
  /// [requestPermission], dopo l'avviso in evidenza (`UiLocationDisclosure`).
  Future<GeoLocation> getCurrentLocation();

  /// Lo stato del permesso di posizione, senza chiederlo.
  Future<LocationPermissionStatus> checkPermission();

  /// Mostra la richiesta di sistema del permesso (se il sistema può ancora
  /// mostrarla) e ritorna lo stato che ne risulta.
  Future<LocationPermissionStatus> requestPermission();

  /// `true` se, mentre si è online, la posizione continua a essere seguita
  /// anche con l'app in background (Android: foreground service di
  /// [watchPosition]); `false` dove si segue solo in primo piano (iOS).
  bool get keepsTrackingInBackground;

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
