/// Lingua dell'app, scelta dal menu laterale. `system` segue la lingua del
/// telefono (nessun codice) — le altre forzano quella lingua a prescindere
/// dal sistema.
enum AppLanguage {
  system,
  english,
  italian,
  german,
  spanish,
  french,
  arabic;

  /// Codice IETF (`en`/`it`/`de`/`es`/`fr`/`ar`) da passare a `Locale`,
  /// `null` per `system`.
  String? get languageCode => switch (this) {
    AppLanguage.system => null,
    AppLanguage.english => 'en',
    AppLanguage.italian => 'it',
    AppLanguage.german => 'de',
    AppLanguage.spanish => 'es',
    AppLanguage.french => 'fr',
    AppLanguage.arabic => 'ar',
  };
}
