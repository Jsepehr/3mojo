import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/nearby/domain/repositories/nearby_repository.dart';
import 'get_current_location_usecase.dart';

/// Azione: prendi la mia posizione, poi chiedi chi c'è entro `radiusMeters`
/// (100, regola di business fissa). Compone `GetCurrentLocationUseCase`
/// invece di dipendere direttamente da `LocationRepository`.
class GetNearbyPeopleUseCase implements UseCase<List<NearbyPerson>, NoParams> {
  const GetNearbyPeopleUseCase({
    required GetCurrentLocationUseCase getCurrentLocationUseCase,
    required NearbyRepository nearbyRepository,
  }) : _getCurrentLocationUseCase = getCurrentLocationUseCase,
       _nearbyRepository = nearbyRepository;

  static const double radiusMeters = 100;

  final GetCurrentLocationUseCase _getCurrentLocationUseCase;
  final NearbyRepository _nearbyRepository;

  @override
  Future<Either<Failure, List<NearbyPerson>>> call(NoParams params) async {
    final locationResult = await _getCurrentLocationUseCase(const NoParams());

    return locationResult.match(
      (failure) async => Left(failure),
      (location) => _nearbyRepository.getNearbyPeople(
        location,
        radiusMeters: radiusMeters,
      ),
    );
  }
}
