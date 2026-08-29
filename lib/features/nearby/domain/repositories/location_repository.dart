import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/geo_location.dart';

/// Contratto per leggere la posizione GPS reale del proprio telefono.
abstract class LocationRepository {
  Future<Either<Failure, GeoLocation>> getCurrentLocation();

  /// Aggiornamenti di posizione continui, non una tantum — usato mentre la
  /// sessione è online per tenere la presenza aggiornata (e, su Android,
  /// tenere vivo il processo in background).
  Stream<Either<Failure, GeoLocation>> watchPosition();
}
