import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/geo_location.dart';
import '../entities/nearby_person.dart';

/// Contratto verso il backend `server/`: apre una connessione persistente,
/// mandando la mia presenza (posizione + profilo) e ricevendo da lì in poi
/// chi c'è entro un certo raggio ogni volta che cambia — non più una
/// richiesta alla volta.
abstract class NearbyRepository {
  Stream<Either<Failure, List<NearbyPerson>>> watchNearbyPeople(
    GeoLocation location, {
    required double radiusMeters,
    required String sessionId,
    required String gender,
    required String genderPreference,
    required Uint8List selfieBytes,
  });

  /// Manda un aggiornamento di posizione sulla connessione già aperta da
  /// [watchNearbyPeople].
  void updatePosition(GeoLocation location);

  Future<Either<Failure, Unit>> stopBeingVisible(String sessionId);
}
