import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/profile.dart';
import 'get_profile_usecase.dart';
import 'save_profile_usecase.dart';

/// Azione: riconferma il consenso al dato sensibile per il **testo attuale**
/// ([Profile.currentSensitiveConsentVersion]) sul profilo già salvato — per
/// chi aveva acconsentito a una versione precedente, a cui lo Start lo
/// richiede (`SensitiveDataConsentRequiredFailure`). Gemello di
/// `AcceptTermsUseCase`: compone `GetProfileUseCase` e `SaveProfileUseCase`,
/// così la riconferma passa dalle stesse regole di ogni altro salvataggio.
/// Senza profilo: `ProfileMissingFailure`.
class RenewSensitiveConsentUseCase implements UseCase<Unit, NoParams> {
  const RenewSensitiveConsentUseCase({
    required GetProfileUseCase getProfileUseCase,
    required SaveProfileUseCase saveProfileUseCase,
  }) : _getProfileUseCase = getProfileUseCase,
       _saveProfileUseCase = saveProfileUseCase;

  final GetProfileUseCase _getProfileUseCase;
  final SaveProfileUseCase _saveProfileUseCase;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final result = await _getProfileUseCase(const NoParams());
    switch (result) {
      case Left(:final value):
        return Left(value);
      case Right(value: null):
        return const Left(ProfileMissingFailure());
      case Right(:final value?):
        return _saveProfileUseCase(
          Profile(
            gender: value.gender,
            lookingFor: value.lookingFor,
            isAdultConfirmed: value.isAdultConfirmed,
            acceptedSensitiveConsentVersion:
                Profile.currentSensitiveConsentVersion,
            defaultIntent: value.defaultIntent,
            languages: value.languages,
            showGender: value.showGender,
            acceptedTermsVersion: value.acceptedTermsVersion,
          ),
        );
    }
  }
}
