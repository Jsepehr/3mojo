import '/core/errors/failures.dart';
import '/features/profile/domain/entities/profile.dart';
import '/l10n/generated/app_localizations.dart';

/// Testi ed emoji per i valori del profilo, condivisi da pagina profilo,
/// Start e lista "Vicinanze" — un solo posto dove cambiarli. Non è un
/// widget: solo la traduzione da valore di dominio a testo.
class ProfileLabels {
  const ProfileLabels._();

  static String gender(AppLocalizations l10n, Gender gender) =>
      switch (gender) {
        Gender.male => l10n.male,
        Gender.female => l10n.female,
        Gender.nonBinary => l10n.non_binary,
        Gender.unspecified => l10n.prefer_not_to_say,
      };

  /// Come compare un genere in "chi vuoi incontrare" (al plurale).
  static String lookingFor(AppLocalizations l10n, Gender gender) =>
      switch (gender) {
        Gender.male => l10n.men,
        Gender.female => l10n.women,
        Gender.nonBinary => l10n.non_binary_people,
        Gender.unspecified => l10n.everyone,
      };

  static String intent(AppLocalizations l10n, MeetIntent intent) =>
      switch (intent) {
        MeetIntent.chat => l10n.a_quick_chat,
        MeetIntent.friendship => l10n.friendship,
        MeetIntent.meetPeople => l10n.meeting_new_people,
        MeetIntent.openToAnything => l10n.open_to_anything,
      };

  /// Niente cuore né rosso: quelli restano riservati al match.
  static String intentEmoji(MeetIntent intent) => switch (intent) {
    MeetIntent.chat => '☕',
    MeetIntent.friendship => '🤝',
    MeetIntent.meetPeople => '🙂',
    MeetIntent.openToAnything => '✨',
  };

  /// Il testo per un errore di salvataggio/lettura/cancellazione del
  /// profilo, scelto dal **tipo** di [failure] — mai il suo `message`.
  static String failure(AppLocalizations l10n, Failure failure) =>
      switch (failure) {
        AdultConfirmationRequiredFailure() => l10n.profile_error_adult_required,
        LookingForRequiredFailure() => l10n.profile_error_looking_for_required,
        TooManyLanguagesFailure(:final maxLanguages) =>
          l10n.profile_error_too_many_languages(maxLanguages),
        UnsupportedLanguageFailure() => l10n.profile_error_unsupported_language,
        SensitiveDataConsentRequiredFailure() =>
          l10n.profile_error_consent_required,
        CacheFailure() => l10n.profile_error_storage,
        _ => l10n.action_failed_generic,
      };
}
