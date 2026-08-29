import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/nearby/domain/repositories/nearby_repository.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/get_current_session_usecase.dart';
import 'get_current_location_usecase.dart';
import 'watch_position_usecase.dart';

/// Azione: apri la connessione con chi sono (per farmi riconoscere dal
/// server) e la mia posizione, poi resta in ascolto di chi c'è entro
/// `radiusMeters` (100, regola di business fissa) — aggiornato dal server
/// stesso ogni volta che qualcosa cambia, non richiesto di nuovo a mano.
/// Compone `GetCurrentSessionUseCase` e `GetCurrentLocationUseCase` invece
/// di dipendere direttamente dai loro repository — sotto-passi genuini di
/// "chi c'è vicino a me ora".
class WatchNearbyPeopleUseCase {
  const WatchNearbyPeopleUseCase({
    required GetCurrentSessionUseCase getCurrentSessionUseCase,
    required GetCurrentLocationUseCase getCurrentLocationUseCase,
    required WatchPositionUseCase watchPositionUseCase,
    required NearbyRepository nearbyRepository,
  }) : _getCurrentSessionUseCase = getCurrentSessionUseCase,
       _getCurrentLocationUseCase = getCurrentLocationUseCase,
       _watchPositionUseCase = watchPositionUseCase,
       _nearbyRepository = nearbyRepository;

  static const double radiusMeters = 150;

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final GetCurrentLocationUseCase _getCurrentLocationUseCase;
  final WatchPositionUseCase _watchPositionUseCase;
  final NearbyRepository _nearbyRepository;

  Stream<Either<Failure, List<NearbyPerson>>> call() async* {
    Failure? firstFailure;
    OnlineSession? session;
    GeoLocation? location;

    final sessionResult = await _getCurrentSessionUseCase(const NoParams());
    sessionResult.match((f) => firstFailure = f, (s) => session = s);

    if (firstFailure != null) {
      yield Left(firstFailure!);
      return;
    }
    if (session == null) {
      yield const Left(
        ValidationFailure('Devi essere online per vedere le persone vicine'),
      );
      return;
    }

    final locationResult = await _getCurrentLocationUseCase(const NoParams());
    locationResult.match((f) => firstFailure = f, (l) => location = l);

    if (firstFailure != null) {
      yield Left(firstFailure!);
      return;
    }

    // Ri-manda la posizione sulla connessione già aperta da
    // `watchNearbyPeople` qui sotto ogni volta che il GPS ne emette una
    // nuova — un side-effect, non fa parte di ciò che questo stream emette.
    // Si ferma da sola quando chi ascolta cancella la sottoscrizione (il
    // `finally` gira comunque). Su Android questo stream è anche ciò che
    // tiene vivo il processo in background (foreground service, vedi
    // `LocationLocalDataSourceImpl.watchPosition`).
    final positionSubscription = _watchPositionUseCase().listen((result) {
      result.match((_) {}, _nearbyRepository.updatePosition);
    });

    try {
      yield* _nearbyRepository.watchNearbyPeople(
        location!,
        radiusMeters: radiusMeters,
        sessionId: session!.sessionId,
        gender: session!.gender.name,
        genderPreference: session!.genderPreference.name,
        selfieBytes: session!.selfieBytes,
      );
    } finally {
      await positionSubscription.cancel();
    }
  }
}
