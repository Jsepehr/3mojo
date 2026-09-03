import 'package:flutter/material.dart';

import '/core/usecases/usecase.dart';
import '/features/settings/domain/entities/app_language.dart';
import '/features/settings/domain/entities/app_theme_mode.dart';
import '/features/settings/domain/usecases/get_language_usecase.dart';
import '/features/settings/domain/usecases/get_theme_mode_usecase.dart';
import '/features/settings/domain/usecases/set_language_usecase.dart';
import '/features/settings/domain/usecases/set_theme_mode_usecase.dart';

/// Lingua e tema dell'app: caricati da disco all'avvio, cambiabili dal menu
/// laterale. `MaterialApp` osserva `locale` e `themeMode` per ricostruirsi
/// con la scelta corrente (`locale` `null` per seguire la lingua di sistema).
class ProSettings extends ChangeNotifier {
  ProSettings({
    required GetLanguageUseCase getLanguageUseCase,
    required SetLanguageUseCase setLanguageUseCase,
    required GetThemeModeUseCase getThemeModeUseCase,
    required SetThemeModeUseCase setThemeModeUseCase,
  }) : _getLanguageUseCase = getLanguageUseCase,
       _setLanguageUseCase = setLanguageUseCase,
       _getThemeModeUseCase = getThemeModeUseCase,
       _setThemeModeUseCase = setThemeModeUseCase {
    _load();
  }

  final GetLanguageUseCase _getLanguageUseCase;
  final SetLanguageUseCase _setLanguageUseCase;
  final GetThemeModeUseCase _getThemeModeUseCase;
  final SetThemeModeUseCase _setThemeModeUseCase;

  AppLanguage _language = AppLanguage.system;
  AppThemeMode _appThemeMode = AppThemeMode.light;

  AppLanguage get language => _language;
  Locale? get locale =>
      _language.languageCode == null ? null : Locale(_language.languageCode!);

  AppThemeMode get appThemeMode => _appThemeMode;
  bool get isDarkMode => _appThemeMode == AppThemeMode.dark;
  ThemeMode get themeMode =>
      _appThemeMode == AppThemeMode.dark ? ThemeMode.dark : ThemeMode.light;

  Future<void> _load() async {
    final languageResult = await _getLanguageUseCase(const NoParams());
    languageResult.match((_) {}, (language) => _language = language);

    final themeModeResult = await _getThemeModeUseCase(const NoParams());
    themeModeResult.match((_) {}, (mode) => _appThemeMode = mode);

    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    final result = await _setLanguageUseCase(language);
    result.match((_) {}, (_) => _language = language);
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final result = await _setThemeModeUseCase(mode);
    result.match((_) {}, (_) => _appThemeMode = mode);
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) {
    return setThemeMode(enabled ? AppThemeMode.dark : AppThemeMode.light);
  }
}
