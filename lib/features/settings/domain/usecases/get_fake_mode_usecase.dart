import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

/// Azione: i datasource finti (nessuna rete) sono attivi? Regola: solo se
/// la modalità finta è **disponibile** in questo build ([isAvailable], in
/// pratica i build di debug). In un build di release la risposta è sempre
/// `false`, anche se un valore salvato da una versione precedente dice
/// "finti" — un'app pubblicata non deve mai girare su dati inventati.
class GetFakeModeUseCase implements UseCase<bool, NoParams> {
  const GetFakeModeUseCase(this._repository, {required this.isAvailable});

  final SettingsRepository _repository;
  final bool isAvailable;

  @override
  Future<Either<Failure, bool>> call(NoParams params) async {
    if (!isAvailable) return const Right(false);
    return _repository.getFakeMode();
  }
}
