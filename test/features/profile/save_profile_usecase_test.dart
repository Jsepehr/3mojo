import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/profile/domain/usecases/save_profile_usecase.dart';

import '../../support/fake_repositories.dart';

Profile _profile({
  Gender gender = Gender.female,
  Set<Gender> lookingFor = const {Gender.male},
  bool isAdultConfirmed = true,
  int acceptedSensitiveConsentVersion = Profile.currentSensitiveConsentVersion,
  List<String> languages = const [],
  bool showGender = false,
  int acceptedTermsVersion = Profile.currentTermsVersion,
}) => Profile(
  gender: gender,
  lookingFor: lookingFor,
  isAdultConfirmed: isAdultConfirmed,
  acceptedSensitiveConsentVersion: acceptedSensitiveConsentVersion,
  languages: languages,
  showGender: showGender,
  acceptedTermsVersion: acceptedTermsVersion,
);

void main() {
  late FakeProfileRepository repository;
  late SaveProfileUseCase saveProfile;

  setUp(() {
    repository = FakeProfileRepository();
    saveProfile = SaveProfileUseCase(repository);
  });

  Future<Failure?> rejection(Profile profile) async {
    final result = await saveProfile(profile);
    expect(repository.saved, isNull, reason: 'nothing must be stored');
    return result.getLeft().toNullable();
  }

  test('rejects a profile that has not accepted the current terms of '
      'use, and keeps the accepted version when saving', () async {
    expect(
      await rejection(_profile(acceptedTermsVersion: 0)),
      isA<TermsNotAcceptedFailure>(),
    );

    final result = await saveProfile(_profile());

    expect(result.isRight(), isTrue);
    expect(repository.saved?.acceptedTermsVersion, Profile.currentTermsVersion);
    expect(repository.saved?.hasAcceptedCurrentTerms, isTrue);
  });

  test('rejects a profile without the 18+ confirmation', () async {
    expect(
      await rejection(_profile(isAdultConfirmed: false)),
      isA<AdultConfirmationRequiredFailure>(),
    );
  });

  test('rejects an empty "who do you want to meet"', () async {
    expect(
      await rejection(_profile(lookingFor: const {})),
      isA<LookingForRequiredFailure>(),
    );
  });

  test('rejects "unspecified" as something to look for', () async {
    expect(
      await rejection(_profile(lookingFor: const {Gender.unspecified})),
      isA<LookingForRequiredFailure>(),
    );
  });

  test('rejects more languages than Profile.maxLanguages, and says the '
      'limit', () async {
    final tooMany = Profile.supportedLanguages
        .take(Profile.maxLanguages + 1)
        .toList();

    final failure = await rejection(_profile(languages: tooMany));

    expect(failure, isA<TooManyLanguagesFailure>());
    expect(
      (failure! as TooManyLanguagesFailure).maxLanguages,
      Profile.maxLanguages,
    );
  });

  test('an unsupported language has its own error, not "too many"', () async {
    expect(
      await rejection(_profile(languages: const ['xx'])),
      isA<UnsupportedLanguageFailure>(),
    );
  });

  test('requires consent when gender or preference reveal something', () async {
    expect(
      await rejection(_profile(acceptedSensitiveConsentVersion: 0)),
      isA<SensitiveDataConsentRequiredFailure>(),
    );
    // Anche solo il genere dichiarato, cercando "tutti", rivela qualcosa.
    expect(
      await rejection(
        _profile(
          lookingFor: Profile.searchableGenders,
          acceptedSensitiveConsentVersion: 0,
        ),
      ),
      isA<SensitiveDataConsentRequiredFailure>(),
    );
  });

  test('the neutral path ("prefer not to say" + everyone) is saved without '
      'consent', () async {
    final result = await saveProfile(
      _profile(
        gender: Gender.unspecified,
        lookingFor: Profile.searchableGenders,
        acceptedSensitiveConsentVersion: 0,
      ),
    );

    expect(result.isRight(), isTrue);
    expect(repository.saved, isNotNull);
  });

  test('the neutral path ("prefer not to say" + everyone) needs no consent '
      'and stores none', () async {
    final result = await saveProfile(
      _profile(
        gender: Gender.unspecified,
        lookingFor: Profile.searchableGenders,
        acceptedSensitiveConsentVersion: Profile.currentSensitiveConsentVersion,
      ),
    );

    expect(result.isRight(), isTrue);
    expect(repository.saved!.needsSensitiveDataConsent, isFalse);
    expect(repository.saved!.acceptedSensitiveConsentVersion, 0);
  });

  test('"show my gender" is switched off for "prefer not to say"', () async {
    await saveProfile(
      _profile(
        gender: Gender.unspecified,
        lookingFor: Profile.searchableGenders,
        showGender: true,
      ),
    );

    expect(repository.saved!.showGender, isFalse);
  });

  test('saves a valid profile as is', () async {
    final profile = _profile(languages: const ['it', 'en'], showGender: true);

    final result = await saveProfile(profile);

    expect(result.isRight(), isTrue);
    expect(repository.saved, profile);
  });
}
