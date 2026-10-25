import 'package:fpdart/fpdart.dart';
import 'package:uuid/uuid.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/profile/domain/entities/profile.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/repositories/session_repository.dart';
import '/features/session/domain/usecases/take_selfie_usecase.dart';

/// Azione: fai partire la sessione **della demo dichiarata** — sul
/// `SessionRepository` della demo (in memoria, separato da quello reale:
/// lo sceglie `DemoScope`), mai su quello vero.
///
/// Regole della demo:
/// - il "selfie" è quello che dà `TakeSelfieUseCase` della demo: un avatar
///   illustrato (`SelfieLocalDataSourceFakeImpl`), nessuna fotocamera;
/// - il profilo è sempre [demoProfile], **neutro** ("preferisco non dirlo"
///   e "tutti"): il profilo vero (genere, chi cerchi, dato sensibile) non
///   entra nella demo, e la demo funziona anche prima di averlo compilato;
/// - nessun controllo del volto, nessun termine da accettare: nella demo
///   non c'è nessun altro a cui mostrare nulla.
class StartDemoSessionUseCase implements UseCase<OnlineSession, NoParams> {
  const StartDemoSessionUseCase({
    required SessionRepository repository,
    required TakeSelfieUseCase takeSelfieUseCase,
  }) : _repository = repository,
       _takeSelfieUseCase = takeSelfieUseCase;

  /// Il profilo della demo: percorso neutro, nessun dato sensibile.
  static const Profile demoProfile = Profile(
    gender: Gender.unspecified,
    lookingFor: Profile.searchableGenders,
    isAdultConfirmed: true,
    defaultIntent: MeetIntent.chat,
    acceptedTermsVersion: Profile.currentTermsVersion,
  );

  final SessionRepository _repository;
  final TakeSelfieUseCase _takeSelfieUseCase;

  @override
  Future<Either<Failure, OnlineSession>> call(NoParams params) async {
    final selfie = await _takeSelfieUseCase(const NoParams());
    switch (selfie) {
      case Left(:final value):
        return Left(value);
      case Right(value: null):
        return const Left(SelfieMissingFailure());
      case Right(:final value?):
        return _repository.startSession(
          sessionId: 'demo-${const Uuid().v4()}',
          selfieBytes: value,
          profile: demoProfile,
          intent: demoProfile.defaultIntent,
        );
    }
  }
}
