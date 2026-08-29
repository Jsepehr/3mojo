import 'dart:async';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/nearby/data/datasources/nearby_remote_data_source.dart';
import '/features/nearby/data/models/nearby_person_model.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/nearby/domain/repositories/nearby_repository.dart';

/// Apre la connessione persistente verso il backend reale e traduce ciò che
/// arriva; rifiltra di nuovo entro `radiusMeters` come difesa in più anche
/// se il server dovesse già filtrare.
class NearbyRepositoryImpl implements NearbyRepository {
  const NearbyRepositoryImpl(this._remoteDataSource);

  final NearbyRemoteDataSource _remoteDataSource;

  @override
  Stream<Either<Failure, List<NearbyPerson>>> watchNearbyPeople(
    GeoLocation location, {
    required double radiusMeters,
    required String sessionId,
    required String gender,
    required String genderPreference,
    required Uint8List selfieBytes,
  }) {
    final upstream = _remoteDataSource.connect(
      sessionId: sessionId,
      latitude: location.latitude,
      longitude: location.longitude,
      gender: gender,
      genderPreference: genderPreference,
      selfieBytes: selfieBytes,
    );

    return upstream.transform(
      StreamTransformer<
        List<NearbyPersonModel>,
        Either<Failure, List<NearbyPerson>>
      >.fromHandlers(
        handleData: (people, sink) => sink.add(
          Right(
            people.where((p) => p.distanceMeters <= radiusMeters).toList(),
          ),
        ),
        handleError: (error, stackTrace, sink) =>
            sink.add(Left(UnexpectedFailure(error.toString()))),
      ),
    );
  }

  @override
  void updatePosition(GeoLocation location) {
    _remoteDataSource.updatePosition(
      latitude: location.latitude,
      longitude: location.longitude,
    );
  }

  @override
  Future<Either<Failure, Unit>> stopBeingVisible(String sessionId) async {
    try {
      await _remoteDataSource.disconnect();
      return const Right(unit);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
