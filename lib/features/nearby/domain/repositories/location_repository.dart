import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/background_location_notice.dart';
import '../entities/geo_location.dart';
import '../entities/location_permission_status.dart';

/// Contratto per leggere la posizione GPS reale del proprio telefono.
abstract class LocationRepository {
  /// La posizione attuale. Non chiede il permesso: se manca,
  /// `LocationPermissionFailure` (la richiesta passa da [requestPermission],
  /// dopo l'avviso in evidenza).
  Future<Either<Failure, GeoLocation>> getCurrentLocation();

  /// Lo stato del permesso di posizione, **senza** chiederlo.
  Future<Either<Failure, LocationPermissionStatus>> checkPermission();

  /// Chiede il permesso al sistema e ritorna lo stato che ne risulta.
  Future<Either<Failure, LocationPermissionStatus>> requestPermission();

  /// `true` se da online la posizione continua a essere usata anche con
  /// l'app in background (Android, con notifica fissa); `false` dove si usa
  /// solo con l'app in primo piano (iOS).
  bool get keepsTrackingInBackground;

  /// Aggiornamenti di posizione continui, non una tantum — usato mentre la
  /// sessione è online per tenere la presenza aggiornata (e, su Android,
  /// tenere vivo il processo in background, con una notifica i cui testi
  /// sono [notice] — obbligatori, scelti dagli ARB in presentation).
  Stream<Either<Failure, GeoLocation>> watchPosition({
    required BackgroundLocationNotice notice,
  });

  /// Porta l'utente alle impostazioni di sistema della localizzazione.
  Future<Either<Failure, Unit>> openLocationSettings();

  /// Porta l'utente alle impostazioni di sistema di questa app (permessi).
  Future<Either<Failure, Unit>> openAppSettings();
}
