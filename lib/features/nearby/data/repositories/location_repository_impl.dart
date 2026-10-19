import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '/core/errors/exceptions.dart';
import '/core/errors/failures.dart';
import '/features/nearby/data/datasources/location_local_data_source.dart';
import '/features/nearby/domain/entities/background_location_notice.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import '/features/nearby/domain/repositories/location_repository.dart';

/// Traduce le eccezioni del datasource GPS (permesso negato, GPS
/// disattivato) nei corrispondenti `Failure`.
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

  @override
  Stream<Either<Failure, GeoLocation>> watchPosition({
    required BackgroundLocationNotice notice,
  }) {
    return _localDataSource
        .watchPosition(notice: notice)
        .transform(
          StreamTransformer<
            GeoLocation,
            Either<Failure, GeoLocation>
          >.fromHandlers(
            handleData: (location, sink) => sink.add(Right(location)),
            handleError: (error, stackTrace, sink) =>
                sink.add(Left(UnexpectedFailure(error.toString()))),
          ),
        );
  }

  @override
  Future<Either<Failure, Unit>> openLocationSettings() =>
      _openSettings(_localDataSource.openLocationSettings);

  @override
  Future<Either<Failure, Unit>> openAppSettings() =>
      _openSettings(_localDataSource.openAppSettings);

  Future<Either<Failure, Unit>> _openSettings(
    Future<bool> Function() open,
  ) async {
    try {
      final opened = await open();
      return opened
          ? const Right(unit)
          : const Left(UnexpectedFailure('Could not open the settings'));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
