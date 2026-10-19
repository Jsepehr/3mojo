import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/profile/domain/usecases/delete_profile_usecase.dart';
import 'end_session_usecase.dart';
import 'get_current_session_usecase.dart';

/// Azione: cancella il profilo (e con lui il consenso al dato sensibile).
/// Regola: **se si è online, prima si chiude la sessione** — il server tiene
/// genere e "chi cerchi" in RAM finché la sessione vive, e continuerebbe a
/// usarli per il matching dopo che l'utente ha ritirato il consenso. Se la
/// chiusura locale fallisce il profilo non viene cancellato (si resterebbe
/// online con un profilo che non esiste più).
///
/// Vive in `session/` e non in `profile/` perché compone [EndSessionUseCase]:
/// `session/` dipende già da `profile/` (lo Start legge il profilo), non
/// il contrario — così non nasce un ciclo tra le due feature.
class WithdrawProfileUseCase implements UseCase<Unit, NoParams> {
  const WithdrawProfileUseCase({
    required GetCurrentSessionUseCase getCurrentSessionUseCase,
    required EndSessionUseCase endSessionUseCase,
    required DeleteProfileUseCase deleteProfileUseCase,
  }) : _getCurrentSessionUseCase = getCurrentSessionUseCase,
       _endSessionUseCase = endSessionUseCase,
       _deleteProfileUseCase = deleteProfileUseCase;

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final EndSessionUseCase _endSessionUseCase;
  final DeleteProfileUseCase _deleteProfileUseCase;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final current = await _getCurrentSessionUseCase(const NoParams());
    // Nel dubbio (sessione illeggibile) si chiude comunque: chiudere una
    // sessione che non c'è non costa nulla.
    final mightBeOnline = current.match(
      (_) => true,
      (session) => session != null,
    );

    if (mightBeOnline) {
      final ended = await _endSessionUseCase(const NoParams());
      if (ended.isLeft()) return ended;
    }
    return _deleteProfileUseCase(const NoParams());
  }
}
