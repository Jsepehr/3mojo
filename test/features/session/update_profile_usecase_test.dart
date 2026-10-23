import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/profile/domain/usecases/save_profile_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/end_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/update_profile_usecase.dart';

import '../../support/fake_repositories.dart';

/// Sessione che ricorda quale profilo era salvato quando è stata chiusa:
/// serve a provare che la sessione si chiude **prima** del salvataggio.
class _RecordingSessionRepository extends FakeSessionRepository {
  _RecordingSessionRepository(this.profiles, {super.current});

  final FakeProfileRepository profiles;
  Profile? savedAtEnd;

  @override
  Future<Either<Failure, Unit>> endSession() {
    savedAtEnd = profiles.saved;
    return super.endSession();
  }
}

/// Sessione la cui chiusura locale fallisce.
class _StuckSessionRepository extends FakeSessionRepository {
  _StuckSessionRepository() : super(current: testSession('s1'));

  @override
  Future<Either<Failure, Unit>> endSession() async =>
      const Left(CacheFailure('cannot end'));
}

/// Il profilo della sessione online è `testProfile` (uomo, cerca tutti,
/// consenso al testo attuale, genere non mostrato).
Profile _edit({
  Gender gender = Gender.male,
  Set<Gender> lookingFor = Profile.searchableGenders,
  bool showGender = false,
  int consent = Profile.currentSensitiveConsentVersion,
  List<String> languages = const [],
  MeetIntent? defaultIntent,
  bool isAdultConfirmed = true,
}) => Profile(
  gender: gender,
  lookingFor: lookingFor,
  isAdultConfirmed: isAdultConfirmed,
  acceptedSensitiveConsentVersion: consent,
  defaultIntent: defaultIntent,
  languages: languages,
  showGender: showGender,
  acceptedTermsVersion: Profile.currentTermsVersion,
);

void main() {
  late FakeProfileRepository profiles;
  late _RecordingSessionRepository sessions;
  late UpdateProfileUseCase update;

  UpdateProfileUseCase build(FakeSessionRepository sessions) =>
      UpdateProfileUseCase(
        getCurrentSessionUseCase: GetCurrentSessionUseCase(sessions),
        endSessionUseCase: EndSessionUseCase(repository: sessions),
        saveProfileUseCase: SaveProfileUseCase(profiles),
      );

  setUp(() {
    profiles = FakeProfileRepository(saved: testProfile);
    sessions = _RecordingSessionRepository(
      profiles,
      current: testSession('s1'),
    );
    update = build(sessions);
  });

  group('online, a change to the sensitive data ends the session first', () {
    final sensitiveChanges = {
      'gender': _edit(gender: Gender.nonBinary),
      'who you want to meet': _edit(lookingFor: const {Gender.female}),
      '"show my gender"': _edit(showGender: true),
      'withdrawing the consent (neutral path)': _edit(
        gender: Gender.unspecified,
        consent: 0,
      ),
    };

    for (final MapEntry(key: what, value: edited) in sensitiveChanges.entries) {
      test(what, () async {
        expect(await update.endsSession(edited), isTrue);

        final result = await update(edited);

        expect(result.isRight(), isTrue);
        expect(sessions.endSessionCalls, 1);
        expect(sessions.current, isNull);
        // Chiusa quando c'era ancora il profilo di prima: poi il salvataggio.
        expect(sessions.savedAtEnd, testProfile);
        expect(profiles.saved!.gender, edited.gender);
        expect(profiles.saved!.showGender, edited.showGender);
      });
    }
  });

  test('online, languages and usual intent apply from the next Start: the '
      'session stays', () async {
    final edited = _edit(
      languages: const ['it'],
      defaultIntent: MeetIntent.chat,
    );

    expect(await update.endsSession(edited), isFalse);
    final result = await update(edited);

    expect(result.isRight(), isTrue);
    expect(sessions.endSessionCalls, 0);
    expect(sessions.current, isNotNull);
    expect(profiles.saved!.languages, ['it']);
    expect(profiles.saved!.defaultIntent, MeetIntent.chat);
  });

  test('offline, nothing to end: just saved', () async {
    final offline = _RecordingSessionRepository(profiles);
    final updateOffline = build(offline);
    final edited = _edit(gender: Gender.female);

    expect(await updateOffline.endsSession(edited), isFalse);
    final result = await updateOffline(edited);

    expect(result.isRight(), isTrue);
    expect(offline.endSessionCalls, 0);
    expect(profiles.saved!.gender, Gender.female);
  });

  test('a profile that cannot be saved never costs the session', () async {
    final invalid = _edit(gender: Gender.female, isAdultConfirmed: false);

    expect(await update.endsSession(invalid), isFalse);
    final result = await update(invalid);

    expect(
      result.getLeft().toNullable(),
      isA<AdultConfirmationRequiredFailure>(),
    );
    expect(sessions.endSessionCalls, 0);
    expect(sessions.current, isNotNull);
    expect(profiles.saved, testProfile);
  });

  test('if the session cannot be closed, the change is not saved', () async {
    final stuck = build(_StuckSessionRepository());

    final result = await stuck(_edit(gender: Gender.female));

    expect(result.isLeft(), isTrue);
    expect(profiles.saved, testProfile);
  });

  test('changesSensitiveData compares with what the session is using', () {
    expect(
      UpdateProfileUseCase.changesSensitiveData(testProfile, _edit()),
      isFalse,
    );
    expect(
      UpdateProfileUseCase.changesSensitiveData(
        testProfile,
        _edit(lookingFor: {Gender.male, Gender.female, Gender.nonBinary}),
      ),
      isFalse,
      reason: 'same set, different instance',
    );
    expect(
      UpdateProfileUseCase.changesSensitiveData(
        testProfile,
        _edit(lookingFor: {Gender.male, Gender.female}),
      ),
      isTrue,
    );
  });
}
