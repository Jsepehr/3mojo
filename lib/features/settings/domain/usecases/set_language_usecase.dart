import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/app_language.dart';
import '../repositories/settings_repository.dart';

class SetLanguageUseCase implements UseCase<Unit, AppLanguage> {
  SetLanguageUseCase(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(AppLanguage params) {
    return _repository.setLanguage(params);
  }
}
