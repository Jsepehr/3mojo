import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import '/features/nearby/domain/repositories/location_repository.dart';

/// Azione: resta in ascolto della posizione GPS che cambia nel tempo, invece
/// di leggerla una volta sola — usato da `WatchNearbyPeopleUseCase` per
/// tenere aggiornata la presenza per tutta la durata della connessione, non
/// solo alla sua apertura (e, su Android, per tenere vivo il processo anche
/// con l'app in background).
class WatchPositionUseCase {
  const WatchPositionUseCase(this._repository);

  final LocationRepository _repository;

  Stream<Either<Failure, GeoLocation>> call() => _repository.watchPosition();
}
