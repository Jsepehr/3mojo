import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/nearby/domain/repositories/nearby_repository.dart';
import '/features/session/domain/usecases/get_current_session_usecase.dart';
import 'get_current_location_usecase.dart';

/// Azione: prendi chi sono (per farmi riconoscere dal server) e la mia
/// posizione, poi chiedi chi c'è entro `radiusMeters` (100, regola di
/// business fissa). Compone `GetCurrentSessionUseCase` e
/// `GetCurrentLocationUseCase` invece di dipendere direttamente dai loro
/// repository — sotto-passi genuini di "chi c'è vicino a me ora".
class GetNearbyPeopleUseCase implements UseCase<List<NearbyPerson>, NoParams> {
  const GetNearbyPeopleUseCase({
    required GetCurrentSessionUseCase getCurrentSessionUseCase,
    required GetCurrentLocationUseCase getCurrentLocationUseCase,
    required NearbyRepository nearbyRepository,
  }) : _getCurrentSessionUseCase = getCurrentSessionUseCase,
       _getCurrentLocationUseCase = getCurrentLocationUseCase,
       _nearbyRepository = nearbyRepository;

  static const double radiusMeters = 100;

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final GetCurrentLocationUseCase _getCurrentLocationUseCase;
  final NearbyRepository _nearbyRepository;

  @override
  Future<Either<Failure, List<NearbyPerson>>> call(NoParams params) async {
    final sessionResult = await _getCurrentSessionUseCase(const NoParams());

    return sessionResult.match((failure) async => Left(failure), (
      session,
    ) async {
      if (session == null) {
        return const Left(
          ValidationFailure('Devi essere online per vedere le persone vicine'),
        );
      }

      final locationResult = await _getCurrentLocationUseCase(
        const NoParams(),
      );

      return locationResult.match(
        (failure) => Left(failure),
        (location) => _nearbyRepository.getNearbyPeople(
          location,
          radiusMeters: radiusMeters,
          sessionId: session.sessionId,
          gender: session.gender.name,
          genderPreference: session.genderPreference.name,
          selfieBytes: session.selfieBytes,
        ),
      );
    });
  }
}
