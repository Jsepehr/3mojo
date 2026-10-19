import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/profile_repository.dart';

/// Azione, all'avvio dell'app: se è il **primo avvio dopo
/// un'installazione**, cancella tutto ciò che l'archivio cifrato del
/// telefono ha conservato da un'installazione precedente — su iOS il
/// Keychain sopravvive alla disinstallazione, quindi senza questo passo chi
/// reinstalla (o chi riceve il telefono) ritroverebbe il profilo di prima,
/// con genere e "chi cerchi". Poi segna che il primo avvio è fatto.
///
/// Se la cancellazione fallisce il segno **non** viene messo: si riprova al
/// prossimo avvio, invece di lasciare per sempre i dati vecchi.
///
/// Nota: anche chi aggiorna da una versione che non aveva ancora il segno
/// passa da qui una volta (e ricompila il profilo).
class WipeDataFromPreviousInstallUseCase implements UseCase<Unit, NoParams> {
  const WipeDataFromPreviousInstallUseCase(this._repository);

  final ProfileRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final firstLaunch = await _repository.isFirstLaunchAfterInstall();
    switch (firstLaunch) {
      case Left(:final value):
        return Left(value);
      case Right(value: false):
        return const Right(unit);
      case Right(value: true):
        break;
    }

    final wiped = await _repository.deleteAllSecureData();
    if (wiped.isLeft()) return wiped;
    return _repository.markFirstLaunchDone();
  }
}
