import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/geo_location.dart';
import '../repositories/location_repository.dart';

class GetCurrentLocationUseCase implements UseCase<GeoLocation, NoParams> {
  const GetCurrentLocationUseCase(this._repository);

  final LocationRepository _repository;

  @override
  Future<Either<Failure, GeoLocation>> call(NoParams params) =>
      _repository.getCurrentLocation();
}
