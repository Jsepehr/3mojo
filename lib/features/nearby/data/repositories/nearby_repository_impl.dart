import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../../domain/entities/geo_location.dart';
import '../../domain/entities/nearby_person.dart';
import '../../domain/repositories/nearby_repository.dart';
import '../datasources/nearby_remote_data_source.dart';

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
