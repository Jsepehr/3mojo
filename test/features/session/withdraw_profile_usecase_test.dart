import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/usecases/usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/delete_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/get_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/save_profile_usecase.dart';
import 'package:threemojo_app/features/profile/presentation/providers/pro_profile.dart';
import 'package:threemojo_app/features/session/domain/repositories/selfie_repository.dart';
import 'package:threemojo_app/features/session/domain/usecases/check_selfie_has_face_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/end_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/flip_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/session_teardown_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/start_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/take_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/update_profile_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/withdraw_profile_usecase.dart';
import 'package:threemojo_app/features/session/presentation/providers/pro_session.dart';

import '../../support/fake_repositories.dart';

class _FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

/// Passo di pulizia che ricorda se il profilo c'era ancora mentre girava
/// (cioè se il server poteva ancora usarlo).
class _RecordingTeardown implements SessionTeardownUseCase {
  _RecordingTeardown(this.profiles);

  final FakeProfileRepository profiles;
  final calls = <String>[];
  bool profileStillThere = false;

  @override
  Future<Either<Failure, Unit>> call(String sessionId) async {
    calls.add(sessionId);
    profileStillThere = profiles.saved != null;
    return const Right(unit);
  }
}

class _UnusedSelfieRepository implements SelfieRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not needed for this test');
}

/// Sessione la cui chiusura locale fallisce.
class _StuckSessionRepository extends FakeSessionRepository {
  _StuckSessionRepository() : super(current: testSession('s1'));

  @override
  Future<Either<Failure, Unit>> endSession() async =>
      const Left(UnexpectedFailure('cannot end'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  wakelockPlusPlatformInstance = _FakeWakelockPlusPlatform();

  late FakeProfileRepository profiles;

  setUp(() => profiles = FakeProfileRepository(saved: testProfile));

  WithdrawProfileUseCase build(
    FakeSessionRepository sessions, {
    List<SessionTeardownUseCase> teardown = const [],
  }) {
    profiles.sessionsToObserve = sessions;
    return WithdrawProfileUseCase(
      getCurrentSessionUseCase: GetCurrentSessionUseCase(sessions),
      endSessionUseCase: EndSessionUseCase(
        repository: sessions,
        teardownSteps: teardown,
      ),
      deleteProfileUseCase: DeleteProfileUseCase(profiles),
    );
  }

  group('WithdrawProfileUseCase', () {
    test('online: ends the session (server side too) before deleting the '
        'profile', () async {
      final sessions = FakeSessionRepository(current: testSession('s1'));
      final teardown = _RecordingTeardown(profiles);

      final result = await build(sessions, teardown: [teardown])(
        const NoParams(),
      );

      expect(result.isRight(), isTrue);
      expect(sessions.endSessionCalls, 1);
      expect(teardown.calls, ['s1']);
      // Il server è stato avvisato quando il profilo c'era ancora, e il
      // profilo è sparito solo a sessione già chiusa.
      expect(teardown.profileStillThere, isTrue);
      expect(profiles.sessionAtDelete, isNull);
      expect(profiles.saved, isNull);
    });

    test('offline: just deletes the profile', () async {
      final sessions = FakeSessionRepository();

      final result = await build(sessions)(const NoParams());

      expect(result.isRight(), isTrue);
      expect(sessions.endSessionCalls, 0);
      expect(profiles.deleteCalls, 1);
    });

    test(
      'if the session cannot be closed, the profile is not deleted',
      () async {
        final sessions = _StuckSessionRepository();

        final result = await build(sessions)(const NoParams());

        expect(result.isLeft(), isTrue);
        expect(profiles.deleteCalls, 0);
        expect(profiles.saved, testProfile);
      },
    );
  });

  test('deleting the profile from online sends the whole app offline: '
      'ProSession follows the session that ended elsewhere', () async {
    final sessions = FakeSessionRepository(current: testSession('s1'));
    final faces = FakeFaceDetectionRepository();
    final selfies = _UnusedSelfieRepository();
    final proSession = ProSession(
      watchSessionUseCase: WatchSessionUseCase(sessions),
      startSessionUseCase: StartSessionUseCase(
        repository: sessions,
        checkSelfieHasFaceUseCase: CheckSelfieHasFaceUseCase(faces),
        getProfileUseCase: GetProfileUseCase(profiles),
      ),
      endSessionUseCase: EndSessionUseCase(repository: sessions),
      checkSelfieHasFaceUseCase: CheckSelfieHasFaceUseCase(faces),
      takeSelfieUseCase: TakeSelfieUseCase(selfies),
      flipSelfieUseCase: FlipSelfieUseCase(selfies),
    );
    final proProfile = ProProfile(
      getProfileUseCase: GetProfileUseCase(profiles),
      saveProfileUseCase: SaveProfileUseCase(profiles),
      updateProfileUseCase: UpdateProfileUseCase(
        getCurrentSessionUseCase: GetCurrentSessionUseCase(sessions),
        endSessionUseCase: EndSessionUseCase(repository: sessions),
        saveProfileUseCase: SaveProfileUseCase(profiles),
      ),
      withdrawProfileUseCase: build(sessions),
    );
    await Future<void>.delayed(Duration.zero);
    expect(proSession.isOnline, isTrue);
    expect(proProfile.hasProfile, isTrue);

    final deleted = await proProfile.delete();
    await Future<void>.delayed(Duration.zero);

    expect(deleted, isTrue);
    expect(proProfile.hasProfile, isFalse);
    expect(proSession.isOnline, isFalse);

    proSession.dispose();
    proProfile.dispose();
  });
}
