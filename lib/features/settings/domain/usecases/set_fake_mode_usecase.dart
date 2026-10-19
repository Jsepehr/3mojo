import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

/// Azione: accendi/spegni i datasource finti (dal prossimo avvio). Si può
/// accendere solo dove la modalità finta è disponibile ([isAvailable],
/// i build di debug); spegnerla è sempre permesso.
class SetFakeModeUseCase implements UseCase<Unit, bool> {
  const SetFakeModeUseCase(this._repository, {required this.isAvailable});

  final SettingsRepository _repository;
  final bool isAvailable;

  @override
  Future<Either<Failure, Unit>> call(bool enabled) async {
    if (enabled && !isAvailable) {
      return const Left(
        ValidationFailure('Fake mode is not available in this build'),
      );
    }
    return _repository.setFakeMode(enabled);
  }
}
