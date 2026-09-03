import '/features/settings/domain/entities/app_language.dart';
import '/features/settings/domain/entities/app_theme_mode.dart';

/// Contratto per persistere la lingua e il tema scelti sul dispositivo.
abstract class SettingsLocalDataSource {
  Future<AppLanguage> getLanguage();
  Future<void> setLanguage(AppLanguage language);

  Future<AppThemeMode> getThemeMode();
  Future<void> setThemeMode(AppThemeMode themeMode);
}
