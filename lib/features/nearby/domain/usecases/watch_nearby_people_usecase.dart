import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/nearby/domain/entities/background_location_notice.dart';
import '/features/nearby/domain/entities/geo_location.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/nearby/domain/repositories/nearby_repository.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/get_current_session_usecase.dart';
import 'get_current_location_usecase.dart';
import 'watch_position_usecase.dart';

/// Azione: apri la connessione con chi sono (per farmi riconoscere dal
/// server) e la mia posizione, poi resta in ascolto di chi c'è vicino —
/// aggiornato dal server stesso ogni volta che qualcosa cambia, non
/// richiesto di nuovo a mano. Il raggio non è più una costante qui: la
/// regola di visibilità è decisa interamente lato server (raggio base, più
/// eventuali zone d'incontro/hotspot rilevate dal server stesso — il client
/// non ne sa nulla, riceve solo la lista già pronta).
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

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final GetCurrentLocationUseCase _getCurrentLocationUseCase;
  final WatchPositionUseCase _watchPositionUseCase;
  final NearbyRepository _nearbyRepository;

  /// [backgroundNotice]: i testi tradotti della notifica Android che
  /// accompagna la posizione seguita in background (obbligatori: il data
  /// layer non ha testi di riserva).
  Stream<Either<Failure, List<NearbyPerson>>> call({
    required BackgroundLocationNotice backgroundNotice,
  }) async* {
    final OnlineSession session;
    switch (await _getCurrentSessionUseCase(const NoParams())) {
      case Left(:final value):
        yield Left(value);
        return;
      case Right(value: null):
        // Messaggio tecnico, mai mostrato così com'è: la UI sceglie i testi
        // dal tipo di `Failure` (vedi `CmpNearbyErrorState`).
        yield const Left(NotOnlineFailure('No active session'));
        return;
      case Right(:final value?):
        session = value;
    }

    final GeoLocation location;
    switch (await _getCurrentLocationUseCase(const NoParams())) {
      case Left(:final value):
        yield Left(value);
        return;
      case Right(:final value):
        location = value;
    }

    // Il GPS può metterci secondi: nel frattempo può esserci stato un End
    // (o un nuovo Start). Collegarsi ora con la sessione letta prima la
    // renderebbe di nuovo visibile agli altri dopo End — una presenza
    // "fantasma". Si ricontrolla dopo l'attesa, e da qui alla connessione
    // non ci sono altre attese.
    if (!await _isStillCurrent(session)) {
      yield const Left(NotOnlineFailure('Session ended while locating'));
      return;
    }

    // Ri-manda la posizione sulla connessione già aperta da
    // `watchNearbyPeople` qui sotto ogni volta che il GPS ne emette una
    // nuova — un side-effect, non fa parte di ciò che questo stream emette.
    // Si ferma da sola quando chi ascolta cancella la sottoscrizione (il
    // `finally` gira comunque). Su Android questo stream è anche ciò che
    // tiene vivo il processo in background (foreground service, vedi
    // `LocationLocalDataSourceImpl.watchPosition`).
    final positionSubscription = _watchPositionUseCase(notice: backgroundNotice)
        .listen((result) {
          result.match((_) {}, _nearbyRepository.updatePosition);
        });

    try {
      yield* _nearbyRepository.watchNearbyPeople(
        location,
        sessionId: session.sessionId,
        profile: session.profile,
        intent: session.intent,
        selfieBytes: session.selfieBytes,
      );
    } finally {
      await positionSubscription.cancel();
    }
  }

  Future<bool> _isStillCurrent(OnlineSession session) async {
    final result = await _getCurrentSessionUseCase(const NoParams());
    return result.match(
      (_) => false,
      (current) => current?.sessionId == session.sessionId,
    );
  }
}
