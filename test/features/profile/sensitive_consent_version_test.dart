import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/usecases/usecase.dart';
import 'package:threemojo_app/features/profile/data/models/profile_model.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/profile/domain/usecases/get_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/renew_sensitive_consent_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/save_profile_usecase.dart';

import '../../support/fake_repositories.dart';

/// Il consenso al dato sensibile (art. 9) è versionato come i termini
/// d'uso: si sa a quale testo si è detto sì.
void main() {
  Map<String, dynamic> legacyJson({Object? consent}) => {
    'gender': 'female',
    'lookingFor': ['male'],
    'isAdultConfirmed': true,
    'sensitiveDataConsent': ?consent,
    'defaultIntent': null,
    'languages': <String>[],
    'showGender': false,
    'acceptedTermsVersion': Profile.currentTermsVersion,
  };

  group('migration of profiles saved with the old boolean', () {
    test('true becomes version 1 (the text of the time)', () {
      final profile = ProfileModel.fromJson(legacyJson(consent: true));

      expect(
        profile.acceptedSensitiveConsentVersion,
        Profile.legacySensitiveConsentVersion,
      );
      expect(Profile.legacySensitiveConsentVersion, 1);
    });

    test('false or missing becomes 0 (no consent)', () {
      expect(
        ProfileModel.fromJson(
          legacyJson(consent: false),
        ).acceptedSensitiveConsentVersion,
        0,
      );
      expect(
        ProfileModel.fromJson(legacyJson()).acceptedSensitiveConsentVersion,
        0,
      );
    });

    test('the versioned field wins, and is what gets saved from now on', () {
      final json = legacyJson(consent: true)
        ..['acceptedSensitiveConsentVersion'] = 7;
      expect(ProfileModel.fromJson(json).acceptedSensitiveConsentVersion, 7);

      final saved = ProfileModel.fromEntity(testProfile).toJson();
      expect(
        saved['acceptedSensitiveConsentVersion'],
        Profile.currentSensitiveConsentVersion,
      );
      expect(saved.containsKey('sensitiveDataConsent'), isFalse);
      expect(ProfileModel.fromJson(saved).props, testProfile.props);
    });
  });

  group('the rule', () {
    late FakeProfileRepository profiles;
    late SaveProfileUseCase saveProfile;

    setUp(() {
      profiles = FakeProfileRepository();
      saveProfile = SaveProfileUseCase(profiles);
    });

    Profile profile({required int consentVersion, Gender? gender}) => Profile(
      gender: gender ?? Gender.female,
      lookingFor: gender == Gender.unspecified
          ? Profile.searchableGenders
          : const {Gender.male},
      isAdultConfirmed: true,
      acceptedSensitiveConsentVersion: consentVersion,
      acceptedTermsVersion: Profile.currentTermsVersion,
    );

    test('saving needs the consent to the current text: an older one (or '
        'none) is refused', () async {
      final result = await saveProfile(
        profile(consentVersion: Profile.currentSensitiveConsentVersion - 1),
      );

      expect(
        result.getLeft().toNullable(),
        isA<SensitiveDataConsentRequiredFailure>(),
      );
      expect(profiles.saved, isNull);
    });

    test('the consent to the current text is saved with its version', () async {
      await saveProfile(
        profile(consentVersion: Profile.currentSensitiveConsentVersion),
      );

      expect(profiles.saved!.hasCurrentSensitiveConsent, isTrue);
      expect(
        profiles.saved!.acceptedSensitiveConsentVersion,
        Profile.currentSensitiveConsentVersion,
      );
    });

    test('the neutral path needs no consent and keeps none', () async {
      await saveProfile(
        profile(
          gender: Gender.unspecified,
          consentVersion: Profile.currentSensitiveConsentVersion,
        ),
      );

      expect(profiles.saved!.lacksRequiredSensitiveConsent, isFalse);
      expect(profiles.saved!.acceptedSensitiveConsentVersion, 0);
    });

    test('RenewSensitiveConsentUseCase saves the current version and keeps '
        'the rest of the profile', () async {
      profiles.saved = Profile(
        gender: Gender.female,
        lookingFor: const {Gender.male},
        isAdultConfirmed: true,
        acceptedSensitiveConsentVersion:
            Profile.currentSensitiveConsentVersion - 1,
        languages: const ['it'],
        acceptedTermsVersion: Profile.currentTermsVersion,
      );

      final result = await RenewSensitiveConsentUseCase(
        getProfileUseCase: GetProfileUseCase(profiles),
        saveProfileUseCase: saveProfile,
      )(const NoParams());

      expect(result.isRight(), isTrue);
      expect(profiles.saved!.hasCurrentSensitiveConsent, isTrue);
      expect(profiles.saved!.languages, ['it']);
      expect(profiles.saved!.lookingFor, {Gender.male});
    });

    test('RenewSensitiveConsentUseCase without a profile: '
        'ProfileMissingFailure', () async {
      final result = await RenewSensitiveConsentUseCase(
        getProfileUseCase: GetProfileUseCase(profiles),
        saveProfileUseCase: saveProfile,
      )(const NoParams());

      expect(result.getLeft().toNullable(), isA<ProfileMissingFailure>());
    });
  });
}
