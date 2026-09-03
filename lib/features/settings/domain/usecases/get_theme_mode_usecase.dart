import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/app_theme_mode.dart';
import '../repositories/settings_repository.dart';

class GetThemeModeUseCase implements UseCase<AppThemeMode, NoParams> {
  GetThemeModeUseCase(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, AppThemeMode>> call(NoParams params) {
    return _repository.getThemeMode();
  }
}
