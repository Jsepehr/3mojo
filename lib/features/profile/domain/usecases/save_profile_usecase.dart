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
/// - consenso esplicito al dato sensibile, se il profilo lo richiede
///   ([Profile.needsSensitiveDataConsent]);
/// - "mostra il mio genere" non ha senso con "preferisco non dirlo": viene
///   spento invece di rifiutare il salvataggio.
///
/// Ogni regola violata ha il suo `Failure` (la UI ne sceglie il testo, vedi
/// `ProfileLabels.failure`).
class SaveProfileUseCase implements UseCase<Unit, Profile> {
  const SaveProfileUseCase(this._repository);

  final ProfileRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(Profile profile) async {
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
    if (profile.needsSensitiveDataConsent && !profile.sensitiveDataConsent) {
      return const Left(SensitiveDataConsentRequiredFailure());
    }

    final normalized = Profile(
      gender: profile.gender,
      lookingFor: profile.lookingFor,
      isAdultConfirmed: true,
      sensitiveDataConsent:
          profile.needsSensitiveDataConsent && profile.sensitiveDataConsent,
      defaultIntent: profile.defaultIntent,
      languages: languages.toList(),
      showGender: profile.showGender && profile.gender != Gender.unspecified,
    );
    return _repository.saveProfile(normalized);
  }
}
