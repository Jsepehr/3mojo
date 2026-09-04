import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

class GetFakeModeUseCase implements UseCase<bool, NoParams> {
  GetFakeModeUseCase(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, bool>> call(NoParams params) {
    return _repository.getFakeMode();
  }
}
