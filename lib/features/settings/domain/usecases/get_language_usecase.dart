import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/app_language.dart';
import '../repositories/settings_repository.dart';

class GetLanguageUseCase implements UseCase<AppLanguage, NoParams> {
  GetLanguageUseCase(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, AppLanguage>> call(NoParams params) {
    return _repository.getLanguage();
  }
}
