import 'package:fpdart/fpdart.dart';

import '/core/errors/exceptions.dart';
import '/core/errors/failures.dart';
import '../../domain/entities/geo_location.dart';
import '../../domain/repositories/location_repository.dart';
import '../datasources/location_local_data_source.dart';

class LocationRepositoryImpl implements LocationRepository {
  const LocationRepositoryImpl(this._localDataSource);

  final LocationLocalDataSource _localDataSource;

  @override
  Future<Either<Failure, GeoLocation>> getCurrentLocation() async {
    try {
      return Right(await _localDataSource.getCurrentLocation());
    } on LocationDisabledException catch (e) {
      return Left(LocationDisabledFailure(e.message));
    } on LocationPermissionDeniedException catch (e) {
      return Left(LocationPermissionFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
