import 'package:flutter/material.dart';

import '/core/usecases/usecase.dart';
import '/features/settings/domain/entities/app_language.dart';
import '/features/settings/domain/entities/app_theme_mode.dart';
import '/features/settings/domain/usecases/get_fake_mode_usecase.dart';
import '/features/settings/domain/usecases/get_language_usecase.dart';
import '/features/settings/domain/usecases/get_theme_mode_usecase.dart';
import '/features/settings/domain/usecases/set_fake_mode_usecase.dart';
import '/features/settings/domain/usecases/set_language_usecase.dart';
import '/features/settings/domain/usecases/set_theme_mode_usecase.dart';

/// Lingua, tema e modalità finta dell'app: caricati da disco all'avvio,
/// cambiabili dal menu laterale. `MaterialApp` osserva `locale` e
/// `themeMode` per ricostruirsi con la scelta corrente (`locale` `null` per
/// seguire la lingua di sistema). `isFakeMode` sceglie invece, in `app.dart`,
/// tra i datasource reali (richiedono il backend `server/`) e quelli finti
/// (nessuna rete) — la scelta è fatta una sola volta all'avvio dell'app, per
/// non dover chiudere/riaprire connessioni realtime a metà sessione: il
/// drawer avvisa di riavviare l'app dopo averla cambiata.
class ProSettings extends ChangeNotifier {
  ProSettings({
    required GetLanguageUseCase getLanguageUseCase,
    required SetLanguageUseCase setLanguageUseCase,
    required GetThemeModeUseCase getThemeModeUseCase,
    required SetThemeModeUseCase setThemeModeUseCase,
    required GetFakeModeUseCase getFakeModeUseCase,
    required SetFakeModeUseCase setFakeModeUseCase,
  }) : _getLanguageUseCase = getLanguageUseCase,
       _setLanguageUseCase = setLanguageUseCase,
       _getThemeModeUseCase = getThemeModeUseCase,
       _setThemeModeUseCase = setThemeModeUseCase,
       _getFakeModeUseCase = getFakeModeUseCase,
       _setFakeModeUseCase = setFakeModeUseCase {
    _load();
  }

  final GetLanguageUseCase _getLanguageUseCase;
  final SetLanguageUseCase _setLanguageUseCase;
  final GetThemeModeUseCase _getThemeModeUseCase;
  final SetThemeModeUseCase _setThemeModeUseCase;
  final GetFakeModeUseCase _getFakeModeUseCase;
  final SetFakeModeUseCase _setFakeModeUseCase;

  AppLanguage _language = AppLanguage.system;
  AppThemeMode _appThemeMode = AppThemeMode.light;
  bool _fakeMode = false;

  AppLanguage get language => _language;
  Locale? get locale =>
      _language.languageCode == null ? null : Locale(_language.languageCode!);

  AppThemeMode get appThemeMode => _appThemeMode;
  bool get isDarkMode => _appThemeMode == AppThemeMode.dark;
  ThemeMode get themeMode =>
      _appThemeMode == AppThemeMode.dark ? ThemeMode.dark : ThemeMode.light;

  bool get isFakeMode => _fakeMode;

  Future<void> _load() async {
    final languageResult = await _getLanguageUseCase(const NoParams());
    languageResult.match((_) {}, (language) => _language = language);

    final themeModeResult = await _getThemeModeUseCase(const NoParams());
    themeModeResult.match((_) {}, (mode) => _appThemeMode = mode);

    final fakeModeResult = await _getFakeModeUseCase(const NoParams());
    fakeModeResult.match((_) {}, (enabled) => _fakeMode = enabled);

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

  /// Effettivo solo al prossimo avvio dell'app (i datasource reali/finti
  /// sono scelti una sola volta in `main.dart`, prima di costruire l'albero
  /// dei provider) — persiste subito, ma non ricostruisce nulla ora.
  Future<void> setFakeMode(bool enabled) async {
    final result = await _setFakeModeUseCase(enabled);
    result.match((_) {}, (_) => _fakeMode = enabled);
    notifyListeners();
  }
}
