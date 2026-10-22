import 'package:equatable/equatable.dart';

// Errori "di dominio": quello che un repository ritorna (dentro un Either)
// quando un'operazione fallisce. È il linguaggio degli errori che domain/
// e presentation/ capiscono — mai un'eccezione tecnica grezza.

abstract class Failure extends Equatable {
  const Failure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class LocationDisabledFailure extends Failure {
  const LocationDisabledFailure(super.message);
}

class LocationPermissionFailure extends Failure {
  const LocationPermissionFailure(super.message);
}

/// Il server non è raggiungibile o la connessione è caduta (telefono
/// senza rete, server spento, Wi-Fi che cade a metà). Distinta da
/// `UnexpectedFailure` perché la UI la racconta in modo diverso — "sei
/// offline, riproviamo da soli" invece di un errore generico.
class ConnectionFailure extends Failure {
  const ConnectionFailure(super.message);
}

/// Un'azione che ha senso solo con una sessione online (es. guardare chi
/// c'è vicino) chiamata quando non c'è nessuna sessione attiva.
class NotOnlineFailure extends ValidationFailure {
  const NotOnlineFailure(super.message);
}

/// Un messaggio di chat più lungo di quanto ammette il server
/// ([maxLength] unità UTF-16, vedi `SendMessageUseCase.maxTextLength`): non
/// parte nemmeno (il server lo rifiuterebbe, e "Riprova" fallirebbe per
/// sempre).
class MessageTooLongFailure extends ValidationFailure {
  const MessageTooLongFailure(this.maxLength) : super('Message too long');

  final int maxLength;

  @override
  List<Object?> get props => [message, maxLength];
}

/// Una richiesta d'incontro partita verso il server ma mai confermata (né
/// rifiutata) entro il tempo previsto: va considerata persa (vedi
/// `FindLostEncounterRequestsUseCase`) e si può rimandare.
class RequestNotConfirmedFailure extends Failure {
  const RequestNotConfirmedFailure([
    super.message = 'The server never confirmed the request',
  ]);
}

/// C'è già una richiesta d'incontro tra te e questa persona in questa
/// sessione (mandata o ricevuta, in qualsiasi stato): una sola a testa —
/// la stessa regola che applica il server (`alreadyRequested`).
class AlreadyRequestedFailure extends ValidationFailure {
  const AlreadyRequestedFailure(super.message);
}

// --- Start (selfie e profilo) ---
//
// Come per `NotOnlineFailure`/`ConnectionFailure`, il `message` è solo un
// dettaglio tecnico (in inglese, mai a schermo): la UI sceglie il testo
// tradotto dal **tipo** (vedi `SessionFailureTexts`, `ProfileLabels`).

/// Start senza un selfie.
class SelfieMissingFailure extends ValidationFailure {
  const SelfieMissingFailure([super.message = 'A selfie is required']);
}

/// Nel selfie non c'è un volto (controllo sul dispositivo).
class NoFaceInSelfieFailure extends ValidationFailure {
  const NoFaceInSelfieFailure([super.message = 'No face found in the selfie']);
}

/// Il controllo del volto non è riuscito a girare (canale nativo assente o
/// in errore, foto illeggibile): non si sa se c'è un volto, si riprova.
class FaceCheckUnavailableFailure extends Failure {
  const FaceCheckUnavailableFailure(super.message);
}

/// La fotocamera non si è aperta o la foto non si è potuta leggere/
/// elaborare sul telefono.
class SelfieCaptureFailure extends Failure {
  const SelfieCaptureFailure(super.message);
}

/// Start prima di aver compilato il profilo.
class ProfileMissingFailure extends ValidationFailure {
  const ProfileMissingFailure([
    super.message = 'Complete the profile before going online',
  ]);
}

/// Il server ha rifiutato il selfie mandato con la presenza (`rejected`,
/// reason `invalidSelfie`: non è un JPEG valido o è troppo grande). La
/// sessione resta senza foto: va chiusa e rifatto lo Start.
class SelfieRejectedByServerFailure extends Failure {
  const SelfieRejectedByServerFailure([
    super.message = 'The server rejected the selfie',
  ]);
}

/// Il selfie non si è potuto preparare per l'invio sul telefono (ridurlo e
/// ripulirlo dai metadati non è riuscito, o resta troppo grande): la
/// presenza non parte, gli altri non ti vedono. Come per
/// [SelfieRejectedByServerFailure], va chiusa la sessione e rifatto lo
/// Start con un selfie nuovo.
class SelfieNotUsableFailure extends Failure {
  const SelfieNotUsableFailure([
    super.message = 'The selfie could not be prepared for upload',
  ]);
}

/// Troppi Start in poco tempo dalla stessa rete (`error`, code
/// `rateLimited`): il server non accetta la sessione per un po'.
class TooManyStartsFailure extends Failure {
  const TooManyStartsFailure([
    super.message = 'Too many new sessions from this network',
  ]);
}

// --- Profilo ---

/// Maggiore età non confermata.
class AdultConfirmationRequiredFailure extends ValidationFailure {
  const AdultConfirmationRequiredFailure([
    super.message = 'Adult confirmation is required',
  ]);
}

/// "Chi vuoi incontrare" vuoto o con valori non cercabili.
class LookingForRequiredFailure extends ValidationFailure {
  const LookingForRequiredFailure([
    super.message = 'Choose who you want to meet',
  ]);
}

/// Più lingue di quante ne ammette il profilo ([maxLanguages]).
class TooManyLanguagesFailure extends ValidationFailure {
  const TooManyLanguagesFailure(this.maxLanguages)
    : super('Too many languages');

  final int maxLanguages;

  @override
  List<Object?> get props => [message, maxLanguages];
}

/// Una lingua che non è tra quelle supportate.
class UnsupportedLanguageFailure extends ValidationFailure {
  const UnsupportedLanguageFailure([super.message = 'Unsupported language']);
}

/// Genere + "chi cerchi" senza il consenso esplicito al dato sensibile.
class SensitiveDataConsentRequiredFailure extends ValidationFailure {
  const SensitiveDataConsentRequiredFailure([
    super.message = 'Consent to sensitive data is required',
  ]);
}

/// Start (o salvataggio del profilo) senza aver accettato la versione
/// attuale dei termini d'uso (`Profile.currentTermsVersion`): tolleranza
/// zero per contenuti inaccettabili, e chi non li accetta non va online.
class TermsNotAcceptedFailure extends ValidationFailure {
  const TermsNotAcceptedFailure([
    super.message = 'The terms of use must be accepted',
  ]);
}

// --- Sicurezza (blocca/segnala) ---

/// Già mandate in questa sessione tutte le segnalazioni ammesse
/// ([maxReports], come il server, `ModerationStore.maxReportsPerSession`):
/// la segnalazione non parte, ma il blocco sì (vedi `ReportPersonUseCase`).
class TooManyReportsFailure extends ValidationFailure {
  const TooManyReportsFailure(this.maxReports) : super('Too many reports');

  final int maxReports;

  @override
  List<Object?> get props => [message, maxReports];
}
