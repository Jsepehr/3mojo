import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/app_theme_mode.dart';
import '../repositories/settings_repository.dart';

class SetThemeModeUseCase implements UseCase<Unit, AppThemeMode> {
  SetThemeModeUseCase(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(AppThemeMode params) {
    return _repository.setThemeMode(params);
  }
}
