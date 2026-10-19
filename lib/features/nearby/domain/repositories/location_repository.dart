import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/background_location_notice.dart';
import '../entities/geo_location.dart';

/// Contratto per leggere la posizione GPS reale del proprio telefono.
abstract class LocationRepository {
  Future<Either<Failure, GeoLocation>> getCurrentLocation();

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
