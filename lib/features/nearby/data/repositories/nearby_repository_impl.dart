import 'dart:convert';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/nearby/data/datasources/nearby_remote_data_source.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/nearby/domain/repositories/nearby_repository.dart';

/// Manda la mia presenza al backend reale e chiede chi c'è vicino; filtra di
/// nuovo entro `radiusMeters` come difesa in più anche se il server dovesse
/// già filtrare.
class NearbyRepositoryImpl implements NearbyRepository {
  const NearbyRepositoryImpl(this._remoteDataSource);

  final NearbyRemoteDataSource _remoteDataSource;

  @override
  Future<Either<Failure, List<NearbyPerson>>> getNearbyPeople(
    GeoLocation location, {
    required double radiusMeters,
    required String sessionId,
    required String gender,
    required String genderPreference,
    required Uint8List selfieBytes,
  }) async {
    try {
      // Codificare il selfie per il trasporto è un dettaglio tecnico, non
      // una regola di dominio — resta qui, nel layer data.
      final selfieBase64 = selfieBytes.isEmpty
          ? ''
          : base64Encode(selfieBytes);

      final people = await _remoteDataSource
          .reportPresenceAndFetchNearbyPeople(
            sessionId: sessionId,
            latitude: location.latitude,
            longitude: location.longitude,
            radiusMeters: radiusMeters,
            gender: gender,
            genderPreference: genderPreference,
            selfieBase64: selfieBase64,
          );
      final withinRadius = people
          .where((person) => person.distanceMeters <= radiusMeters)
          .toList();
      return Right(withinRadius);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> stopBeingVisible(String sessionId) async {
    try {
      await _remoteDataSource.removePresence(sessionId);
      return const Right(unit);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
