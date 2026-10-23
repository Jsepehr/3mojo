import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/profile.dart';
import '../repositories/profile_repository.dart';

/// Azione: salva il profilo. Le regole vere vivono qui, non nella pagina:
/// - maggiore età confermata (app di incontri: 18+ è un requisito, non
///   una preferenza);
/// - almeno un genere in "chi vuoi incontrare", solo tra quelli cercabili;
/// - al massimo [Profile.maxLanguages] lingue, solo tra quelle supportate;
/// - consenso esplicito al dato sensibile **al testo attuale**
///   ([Profile.currentSensitiveConsentVersion]), se il profilo lo richiede
///   ([Profile.needsSensitiveDataConsent]); nel percorso neutro la versione
///   salvata torna a 0 (non serve, e non resta un consenso "a vuoto");
/// - i termini d'uso attuali accettati ([Profile.hasAcceptedCurrentTerms]):
///   tolleranza zero per contenuti inaccettabili, e conseguenze delle
///   segnalazioni scritte chiaramente prima di usare l'app;
/// - "mostra il mio genere" non ha senso con "preferisco non dirlo": viene
///   spento invece di rifiutare il salvataggio.
///
/// Ogni regola violata ha il suo `Failure` (la UI ne sceglie il testo, vedi
/// `ProfileLabels.failure`). [validate] applica le stesse regole senza
/// salvare: serve a chi deve decidere prima di salvare (es.
/// `UpdateProfileUseCase`, che da online chiude la sessione solo se il
/// salvataggio poi può riuscire).
class SaveProfileUseCase implements UseCase<Unit, Profile> {
  const SaveProfileUseCase(this._repository);

  final ProfileRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(Profile profile) async {
    return switch (validate(profile)) {
      Left(:final value) => Left(value),
      Right(:final value) => _repository.saveProfile(value),
    };
  }

  /// Il profilo come verrebbe salvato (normalizzato), o la prima regola
  /// violata.
  Either<Failure, Profile> validate(Profile profile) {
    if (!profile.isAdultConfirmed) {
      return const Left(AdultConfirmationRequiredFailure());
    }
    if (profile.lookingFor.isEmpty ||
        !Profile.searchableGenders.containsAll(profile.lookingFor)) {
      return const Left(LookingForRequiredFailure());
    }
    final languages = profile.languages.toSet();
    if (!Profile.supportedLanguages.toSet().containsAll(languages)) {
      return const Left(UnsupportedLanguageFailure());
    }
    if (languages.length > Profile.maxLanguages) {
      return const Left(TooManyLanguagesFailure(Profile.maxLanguages));
    }
    if (profile.lacksRequiredSensitiveConsent) {
      return const Left(SensitiveDataConsentRequiredFailure());
    }
    if (!profile.hasAcceptedCurrentTerms) {
      return const Left(TermsNotAcceptedFailure());
    }

    return Right(
      Profile(
        gender: profile.gender,
        lookingFor: profile.lookingFor,
        isAdultConfirmed: true,
        acceptedSensitiveConsentVersion: profile.needsSensitiveDataConsent
            ? profile.acceptedSensitiveConsentVersion
            : 0,
        defaultIntent: profile.defaultIntent,
        languages: languages.toList(),
        showGender: profile.showGender && profile.gender != Gender.unspecified,
        acceptedTermsVersion: profile.acceptedTermsVersion,
      ),
    );
  }
}
