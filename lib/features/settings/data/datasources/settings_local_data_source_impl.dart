import 'package:shared_preferences/shared_preferences.dart';

import '/features/settings/domain/entities/app_language.dart';
import '/features/settings/domain/entities/app_theme_mode.dart';
import 'settings_local_data_source.dart';

/// Persistenza reale su `shared_preferences`: a differenza della sessione
/// online (usa e getta), la lingua e il tema scelti devono sopravvivere alla
/// chiusura dell'app, altrimenti l'utente dovrebbe sceglierli di nuovo ogni
/// volta.
class SettingsLocalDataSourceImpl implements SettingsLocalDataSource {
  static const _languageKey = 'app_language';
  static const _themeModeKey = 'app_theme_mode';
  static const _fakeModeKey = 'app_fake_mode';

  @override
  Future<AppLanguage> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_languageKey);
    return AppLanguage.values.firstWhere(
      (language) => language.name == stored,
      orElse: () => AppLanguage.system,
    );
  }

  @override
  Future<void> setLanguage(AppLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, language.name);
  }

  @override
  Future<AppThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themeModeKey);
    return AppThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => AppThemeMode.light,
    );
  }

  @override
  Future<void> setThemeMode(AppThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, themeMode.name);
  }

  @override
  Future<bool> getFakeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_fakeModeKey) ?? false;
  }

  @override
  Future<void> setFakeMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fakeModeKey, enabled);
  }
}
