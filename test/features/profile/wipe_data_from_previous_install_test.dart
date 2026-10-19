import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/usecases/usecase.dart';
import 'package:threemojo_app/features/profile/data/datasources/profile_local_data_source_impl.dart';
import 'package:threemojo_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:threemojo_app/features/profile/domain/usecases/get_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/wipe_data_from_previous_install_usecase.dart';

import '../../support/fake_repositories.dart';

final _storedProfile = jsonEncode({
  'gender': 'female',
  'lookingFor': ['male'],
  'isAdultConfirmed': true,
  'sensitiveDataConsent': true,
  'defaultIntent': null,
  'languages': <String>[],
  'showGender': false,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WipeDataFromPreviousInstallUseCase', () {
    test(
      'first launch after install: wipes everything, then remembers it',
      () async {
        final profiles = FakeProfileRepository(
          saved: testProfile,
          hasInstallMarker: false,
        );

        final result = await WipeDataFromPreviousInstallUseCase(profiles)(
          const NoParams(),
        );

        expect(result.isRight(), isTrue);
        expect(profiles.wipeCalls, 1);
        expect(profiles.saved, isNull);
        expect(profiles.hasInstallMarker, isTrue);
      },
    );

    test('later launches leave the profile alone', () async {
      final profiles = FakeProfileRepository(saved: testProfile);

      await WipeDataFromPreviousInstallUseCase(profiles)(const NoParams());

      expect(profiles.wipeCalls, 0);
      expect(profiles.saved, testProfile);
    });

    test('if the wipe fails the marker is not set, so it is tried again next '
        'launch', () async {
      final profiles = FakeProfileRepository(
        saved: testProfile,
        hasInstallMarker: false,
      )..wipeResult = const Left(CacheFailure('keychain locked'));

      final result = await WipeDataFromPreviousInstallUseCase(profiles)(
        const NoParams(),
      );

      expect(result.isLeft(), isTrue);
      expect(profiles.hasInstallMarker, isFalse);
    });
  });

  test('with the real storage: a profile and an unlock token surviving a '
      'reinstall (iOS Keychain) are gone, and stay saved afterwards', () async {
    FlutterSecureStorage.setMockInitialValues({
      'profile': _storedProfile,
      'paywall_unlock_token': 'token-from-the-previous-install',
    });
    SharedPreferences.setMockInitialValues({});
    final repository = ProfileRepositoryImpl(ProfileLocalDataSourceImpl());
    final wipe = WipeDataFromPreviousInstallUseCase(repository);

    await wipe(const NoParams());

    const storage = FlutterSecureStorage();
    expect(await storage.readAll(), isEmpty);
    expect(
      (await GetProfileUseCase(repository)(const NoParams())).getRight(),
      const Some<Never?>(null),
    );

    // Il profilo compilato dopo resta: il primo avvio è già stato fatto.
    await storage.write(key: 'profile', value: _storedProfile);
    await wipe(const NoParams());
    expect(await storage.read(key: 'profile'), isNotNull);
  });
}
