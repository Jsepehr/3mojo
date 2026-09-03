import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/app_language.dart';
import '../entities/app_theme_mode.dart';

abstract class SettingsRepository {
  Future<Either<Failure, AppLanguage>> getLanguage();

  Future<Either<Failure, Unit>> setLanguage(AppLanguage language);

  Future<Either<Failure, AppThemeMode>> getThemeMode();

  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode themeMode);
}
