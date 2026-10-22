import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/nearby/domain/entities/geo_location.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/nearby/domain/repositories/nearby_repository.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/stop_being_visible_usecase.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/profile/domain/usecases/get_profile_usecase.dart';
import 'package:threemojo_app/features/session/domain/repositories/selfie_repository.dart';
import 'package:threemojo_app/features/session/domain/usecases/check_selfie_has_face_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/end_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/flip_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/start_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/take_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_closed_by_server_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';
import 'package:threemojo_app/features/session/presentation/providers/pro_session.dart';

import '../../support/fake_repositories.dart';

/// Evita il vero platform channel di `wakelock_plus` (non disponibile in
/// un test senza un device/binding) — `ProSession.start`/`end` lo chiamano
/// a ogni cambio di stato, indipendentemente da cosa stiamo testando qui.
class _FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

/// Riproduce esattamente il bug: un `stopBeingVisible` il cui `Future` non
/// si risolve mai (come `WebSocketChannel.sink.close()` bloccato su un
/// socket già rotto), prima che `RealtimeConnection.disconnect()` e
/// `ProSession.end()` avessero un timeout — `ProSession.end()` restava
/// bloccato per sempre prima di azzerare la sessione, e il bottone End
/// sembrava non fare niente.
class _StuckNearbyRepository implements NearbyRepository {
  @override
  Stream<Either<Failure, List<NearbyPerson>>> watchNearbyPeople(
    GeoLocation location, {
    required String sessionId,
    required Profile profile,
    MeetIntent? intent,
    required Uint8List selfieBytes,
  }) => const Stream.empty();

  @override
  void updatePosition(GeoLocation location) {}

  @override
  Future<Either<Failure, Unit>> stopBeingVisible() {
    return Completer<Either<Failure, Unit>>().future;
  }
}

ProSession _buildProSession(
  FakeSessionRepository sessionRepository,
  NearbyRepository nearbyRepository, {
  FakeConnectionRepository? connection,
}) {
  final faceDetectionRepository = FakeFaceDetectionRepository();
  final selfieRepository = _UnusedSelfieRepository();
  return ProSession(
    watchSessionUseCase: WatchSessionUseCase(sessionRepository),
    startSessionUseCase: StartSessionUseCase(
      repository: sessionRepository,
      checkSelfieHasFaceUseCase: CheckSelfieHasFaceUseCase(
        faceDetectionRepository,
      ),
      getProfileUseCase: GetProfileUseCase(
        FakeProfileRepository(saved: testProfile),
      ),
    ),
    endSessionUseCase: EndSessionUseCase(
      repository: sessionRepository,
      teardownSteps: [StopBeingVisibleUseCase(nearbyRepository)],
    ),
    checkSelfieHasFaceUseCase: CheckSelfieHasFaceUseCase(
      faceDetectionRepository,
    ),
    takeSelfieUseCase: TakeSelfieUseCase(selfieRepository),
    flipSelfieUseCase: FlipSelfieUseCase(selfieRepository),
    watchSessionClosedByServerUseCase: connection == null
        ? null
        : WatchSessionClosedByServerUseCase(connection),
  );
}

class _UnusedSelfieRepository implements SelfieRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not needed for this test');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  wakelockPlusPlatformInstance = _FakeWakelockPlusPlatform();

  test('end() completes even if stopBeingVisible never resolves', () {
    fakeAsync((async) {
      final sessionRepository = FakeSessionRepository(
        current: testSession('a'),
      );
      final proSession = _buildProSession(
        sessionRepository,
        _StuckNearbyRepository(),
      );
      // Lascia finire il caricamento iniziale (_load(), dal costruttore).
      async.flushMicrotasks();
      expect(proSession.isOnline, isTrue);

      var done = false;
      proSession.end().then((_) => done = true);
      async.elapse(const Duration(seconds: 4));

      expect(done, isTrue);
      expect(proSession.isOnline, isFalse);
      expect(proSession.isEnding, isFalse);
    });
  });

  test('a double tap on End ends the session only once', () {
    fakeAsync((async) {
      final sessionRepository = FakeSessionRepository(
        current: testSession('a'),
      );
      final proSession = _buildProSession(
        sessionRepository,
        _StuckNearbyRepository(),
      );
      async.flushMicrotasks();

      proSession.end();
      expect(proSession.isEnding, isTrue);
      proSession.end();
      async.elapse(const Duration(seconds: 4));

      expect(sessionRepository.endSessionCalls, 1);
    });
  });

  test('a session closed by the server after reports ends here too', () {
    fakeAsync((async) {
      final sessionRepository = FakeSessionRepository(
        current: testSession('a'),
      );
      final connection = FakeConnectionRepository();
      final proSession = _buildProSession(
        sessionRepository,
        _StuckNearbyRepository(),
        connection: connection,
      );
      async.flushMicrotasks();
      expect(proSession.isOnline, isTrue);

      connection.closures.add(null);
      async.elapse(const Duration(seconds: 4));

      expect(sessionRepository.endSessionCalls, 1);
      expect(proSession.isOnline, isFalse);
    });
  });
}
