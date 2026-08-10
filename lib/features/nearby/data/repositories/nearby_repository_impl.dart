import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/nearby/data/datasources/nearby_remote_data_source.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/nearby/domain/repositories/nearby_repository.dart';

/// Chiama il datasource finto e filtra il risultato entro `radiusMeters`
/// (difesa in più anche se il "backend" dovesse già filtrare).
class NearbyRepositoryImpl implements NearbyRepository {
  const NearbyRepositoryImpl(this._remoteDataSource);

  final NearbyRemoteDataSource _remoteDataSource;

  @override
  Future<Either<Failure, List<NearbyPerson>>> getNearbyPeople(
    GeoLocation location, {
    required double radiusMeters,
  }) async {
    try {
      final people = await _remoteDataSource.fetchNearbyPeople();
      final withinRadius = people
          .where((person) => person.distanceMeters <= radiusMeters)
          .toList();
      return Right(withinRadius);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
