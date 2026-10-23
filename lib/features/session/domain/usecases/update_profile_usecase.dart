import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/profile/domain/entities/profile.dart';
import '/features/profile/domain/usecases/save_profile_usecase.dart';
import 'end_session_usecase.dart';
import 'get_current_session_usecase.dart';

/// Azione: salva le modifiche al profilo fatte dal menu. Regola: **se si è
/// online e la modifica tocca il dato sensibile, prima si chiude la
/// sessione** (art. 7(3) GDPR: ritirare il consenso dev'essere semplice
/// quanto darlo, e deve valere subito). Il server fissa il profilo alla
/// nascita della sessione (`PresenceProfile`) e userebbe i vecchi genere e
/// "chi cerchi" per il matching fino a End, anche dopo che l'utente ha
/// cambiato idea o ritirato il consenso passando al percorso neutro.
///
/// Sensibile ([changesSensitiveData]) = genere, chi cerchi, "mostra il mio
/// genere" o la perdita del consenso al testo attuale, confrontati con la
/// copia del profilo **che la sessione sta usando**. Lingue e intento
/// predefinito no: non sono dati art. 9, l'intento predefinito serve solo a
/// precompilare il prossimo Start e le lingue non valgono la perdita di
/// selfie, richieste e match in corso — valgono dal prossimo Start.
///
/// Prima si valida (le stesse regole di [SaveProfileUseCase]), poi si
/// chiude la sessione e solo allora si salva: un profilo che non si può
/// salvare non fa mai perdere la sessione, e se la chiusura locale fallisce
/// non si salva (si resterebbe online con valori che l'utente ha già
/// ritirato). Come `WithdrawProfileUseCase`, vive in `session/` perché
/// compone [EndSessionUseCase]: `session/` dipende già da `profile/`, non il
/// contrario.
class UpdateProfileUseCase implements UseCase<Unit, Profile> {
  const UpdateProfileUseCase({
    required GetCurrentSessionUseCase getCurrentSessionUseCase,
    required EndSessionUseCase endSessionUseCase,
    required SaveProfileUseCase saveProfileUseCase,
  }) : _getCurrentSessionUseCase = getCurrentSessionUseCase,
       _endSessionUseCase = endSessionUseCase,
       _saveProfileUseCase = saveProfileUseCase;

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final EndSessionUseCase _endSessionUseCase;
  final SaveProfileUseCase _saveProfileUseCase;

  /// Se salvare [updated] al posto di [current] cambia ciò che il server
  /// usa del dato sensibile.
  static bool changesSensitiveData(Profile current, Profile updated) =>
      current.gender != updated.gender ||
      current.lookingFor.length != updated.lookingFor.length ||
      !current.lookingFor.containsAll(updated.lookingFor) ||
      current.showGender != updated.showGender ||
      (current.hasCurrentSensitiveConsent &&
          !updated.hasCurrentSensitiveConsent);

  /// Se salvare [profile] adesso chiuderebbe prima la sessione: per la
  /// conferma in UI, con la stessa regola di [call]. `false` anche se il
  /// profilo non si può salvare (il salvataggio fallirà senza toccare la
  /// sessione).
  Future<bool> endsSession(Profile profile) async {
    final validated = _saveProfileUseCase.validate(profile);
    return switch (validated) {
      Left() => false,
      Right(:final value) => _mustEndSessionFor(value),
    };
  }

  @override
  Future<Either<Failure, Unit>> call(Profile profile) async {
    final validated = _saveProfileUseCase.validate(profile);
    switch (validated) {
      case Left(:final value):
        return Left(value);
      case Right(:final value):
        if (await _mustEndSessionFor(value)) {
          final ended = await _endSessionUseCase(const NoParams());
          if (ended.isLeft()) return ended;
        }
        return _saveProfileUseCase(value);
    }
  }

  Future<bool> _mustEndSessionFor(Profile normalized) async {
    final current = await _getCurrentSessionUseCase(const NoParams());
    return current.match(
      // Nel dubbio (sessione illeggibile) si chiude: chiudere una sessione
      // che non c'è non costa nulla.
      (_) => true,
      (session) =>
          session != null && changesSensitiveData(session.profile, normalized),
    );
  }
}
