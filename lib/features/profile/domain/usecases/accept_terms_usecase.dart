import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/profile.dart';
import 'get_profile_usecase.dart';
import 'save_profile_usecase.dart';

/// Azione: accetta la versione attuale dei termini d'uso per il profilo già
/// salvato — per i profili compilati prima che i termini esistessero (o di
/// una versione precedente), a cui lo Start li chiede
/// (`TermsNotAcceptedFailure`). Compone `GetProfileUseCase` e
/// `SaveProfileUseCase`, così l'accettazione passa dalle stesse regole di
/// ogni altro salvataggio. Senza profilo: `ProfileMissingFailure`.
class AcceptTermsUseCase implements UseCase<Unit, NoParams> {
  const AcceptTermsUseCase({
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
                value.acceptedSensitiveConsentVersion,
            defaultIntent: value.defaultIntent,
            languages: value.languages,
            showGender: value.showGender,
            acceptedTermsVersion: Profile.currentTermsVersion,
          ),
        );
    }
  }
}
