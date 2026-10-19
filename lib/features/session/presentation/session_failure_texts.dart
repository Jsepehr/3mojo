import '/core/errors/failures.dart';
import '/l10n/generated/app_localizations.dart';

/// Il testo per un errore del wizard di Start (selfie, controllo volto,
/// profilo), scelto dal **tipo** di `Failure` — mai il suo `message`, che è
/// un dettaglio tecnico e non va a schermo (come `CmpNearbyErrorState`).
/// Non è un widget: solo la traduzione da errore di dominio a testo.
class SessionFailureTexts {
  const SessionFailureTexts._();

  static String of(AppLocalizations l10n, Failure failure) => switch (failure) {
    SelfieMissingFailure() => l10n.selfie_error_missing,
    NoFaceInSelfieFailure() => l10n.selfie_error_no_face,
    FaceCheckUnavailableFailure() => l10n.selfie_error_check_failed,
    SelfieCaptureFailure() => l10n.selfie_error_camera,
    ProfileMissingFailure() => l10n.start_error_profile_missing,
    CacheFailure() => l10n.profile_error_storage,
    ConnectionFailure() => l10n.action_not_sent_offline,
    _ => l10n.action_failed_generic,
  };
}
