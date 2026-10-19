import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/session_repository.dart';
import 'session_teardown_usecase.dart';

/// Azione: vai offline (bottone End). Orchestra tutto ciò che deve sparire
/// con la sessione:
///
/// 1. la sessione locale si chiude **per prima**: chi sta ancora lavorando
///    per lei (es. `WatchNearbyPeopleUseCase` in attesa del GPS) la
///    ricontrolla dopo ogni attesa e non si ricollega più al server;
/// 2. poi i passi di pulizia delle altre feature ([SessionTeardownUseCase]:
///    smettere di essere visibili, dimenticare richieste e chat), in
///    parallelo e ognuno con un tempo massimo — **best-effort**: se il
///    server non risponde l'uscita locale riesce lo stesso ("usa e getta"
///    vale prima di tutto sul telefono) e il bottone End non resta mai
///    bloccato (è già capitato che sembrasse "non fare niente").
///
/// Ritorna l'esito della chiusura locale: è quella che decide se si è
/// davvero offline.
class EndSessionUseCase implements UseCase<Unit, NoParams> {
  const EndSessionUseCase({
    required SessionRepository repository,
    List<SessionTeardownUseCase> teardownSteps = const [],
    Duration teardownTimeout = defaultTeardownTimeout,
  }) : _repository = repository,
       _teardownSteps = teardownSteps,
       _teardownTimeout = teardownTimeout;

  static const Duration defaultTeardownTimeout = Duration(seconds: 3);

  final SessionRepository _repository;
  final List<SessionTeardownUseCase> _teardownSteps;
  final Duration _teardownTimeout;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final current = await _repository.getCurrentSession();
    final sessionId = current.match(
      (_) => null,
      (session) => session?.sessionId,
    );

    final ended = await _repository.endSession();

    if (sessionId != null) {
      await Future.wait([
        for (final step in _teardownSteps)
          step(sessionId).timeout(
            _teardownTimeout,
            onTimeout: () =>
                const Left(ConnectionFailure('Session teardown timed out')),
          ),
      ]);
    }
    return ended;
  }
}
