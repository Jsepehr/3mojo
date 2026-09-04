import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

class SetFakeModeUseCase implements UseCase<Unit, bool> {
  SetFakeModeUseCase(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(bool params) {
    return _repository.setFakeMode(params);
  }
}
