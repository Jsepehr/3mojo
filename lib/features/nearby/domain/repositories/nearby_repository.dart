import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/profile/domain/entities/profile.dart';
import '../entities/geo_location.dart';
import '../entities/nearby_person.dart';

/// Contratto verso il backend `server/`: apre una connessione persistente,
/// mandando la mia presenza (posizione + profilo) e ricevendo da lì in poi
/// chi c'è vicino ogni volta che cambia — non più una richiesta alla volta.
/// Il raggio di visibilità non è un parametro qui: è una decisione
/// interamente del server (vedi `ConnectionHub`/`HotspotStore` in `server/`).
abstract class NearbyRepository {
  Stream<Either<Failure, List<NearbyPerson>>> watchNearbyPeople(
    GeoLocation location, {
    required String sessionId,
    required Profile profile,
    MeetIntent? intent,
    required Uint8List selfieBytes,
  });

  /// Manda un aggiornamento di posizione sulla connessione già aperta da
  /// [watchNearbyPeople].
  void updatePosition(GeoLocation location);

  /// Chiude la connessione della sessione in corso: il server toglie
  /// subito la presenza dalla vista di tutti.
  Future<Either<Failure, Unit>> stopBeingVisible();
}
