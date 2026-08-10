import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import '/features/nearby/domain/repositories/location_repository.dart';

/// Azione: leggi la posizione GPS attuale del telefono.
class GetCurrentLocationUseCase implements UseCase<GeoLocation, NoParams> {
  const GetCurrentLocationUseCase(this._repository);

  final LocationRepository _repository;

  @override
  Future<Either<Failure, GeoLocation>> call(NoParams params) =>
      _repository.getCurrentLocation();
}
