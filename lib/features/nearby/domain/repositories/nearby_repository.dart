import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/geo_location.dart';
import '../entities/nearby_person.dart';

/// Contratto verso il backend `server/`: manda la mia presenza (posizione +
/// profilo) e chiede chi c'è entro un certo raggio, o mi toglie dalla vista
/// di tutti quando vado offline.
abstract class NearbyRepository {
  Future<Either<Failure, List<NearbyPerson>>> getNearbyPeople(
    GeoLocation location, {
    required double radiusMeters,
    required String sessionId,
    required String gender,
    required String genderPreference,
    required Uint8List selfieBytes,
  });

  Future<Either<Failure, Unit>> stopBeingVisible(String sessionId);
}
