import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/settings/data/datasources/settings_local_data_source.dart';
import '/features/settings/domain/entities/app_language.dart';
import '/features/settings/domain/entities/app_theme_mode.dart';
import '/features/settings/domain/repositories/settings_repository.dart';

/// Passacarte verso il datasource locale, traducendo le eccezioni in `Failure`.
class SettingsRepositoryImpl implements SettingsRepository {
  const SettingsRepositoryImpl(this._localDataSource);

  final SettingsLocalDataSource _localDataSource;

  @override
  Future<Either<Failure, AppLanguage>> getLanguage() async {
    try {
      return Right(await _localDataSource.getLanguage());
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> setLanguage(AppLanguage language) async {
    try {
      await _localDataSource.setLanguage(language);
      return const Right(unit);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, AppThemeMode>> getThemeMode() async {
    try {
      return Right(await _localDataSource.getThemeMode());
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode themeMode) async {
    try {
      await _localDataSource.setThemeMode(themeMode);
      return const Right(unit);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}
