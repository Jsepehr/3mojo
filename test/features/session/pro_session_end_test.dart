import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/nearby/domain/entities/geo_location.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/nearby/domain/repositories/nearby_repository.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/stop_being_visible_usecase.dart';
import 'package:threemojo_app/features/session/domain/entities/online_session.dart';
import 'package:threemojo_app/features/session/domain/repositories/face_detection_repository.dart';
import 'package:threemojo_app/features/session/domain/repositories/session_repository.dart';
import 'package:threemojo_app/features/session/domain/usecases/check_selfie_has_face_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/end_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/start_session_usecase.dart';
import 'package:threemojo_app/features/session/presentation/providers/pro_session.dart';

class _FakeSessionRepository implements SessionRepository {
  OnlineSession? current;

  @override
  Future<Either<Failure, OnlineSession?>> getCurrentSession() async =>
      Right(current);

  @override
  Future<Either<Failure, OnlineSession>> startSession({
    required String sessionId,
    required String selfiePath,
    required Uint8List selfieBytes,
    required Gender gender,
    required GenderPreference genderPreference,
  }) => throw UnimplementedError('not needed for this test');

  @override
  Future<Either<Failure, Unit>> endSession() async {
    current = null;
    return const Right(unit);
  }
}

class _FakeFaceDetectionRepository implements FaceDetectionRepository {
  @override
  Future<Either<Failure, bool>> containsFace(String imagePath) async =>
      const Right(true);
}

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
    required double radiusMeters,
    required String sessionId,
    required String gender,
    required String genderPreference,
    required Uint8List selfieBytes,
  }) => const Stream.empty();

  @override
  void updatePosition(GeoLocation location) {}

  @override
  Future<Either<Failure, Unit>> stopBeingVisible(String sessionId) {
    return Completer<Either<Failure, Unit>>().future;
  }
}

void main() {
  wakelockPlusPlatformInstance = _FakeWakelockPlusPlatform();

  test('end() completes even if stopBeingVisible never resolves', () async {
    final sessionRepository = _FakeSessionRepository()
      ..current = OnlineSession(
        sessionId: 'a',
        selfiePath: '',
        selfieBytes: Uint8List(0),
        gender: Gender.male,
        genderPreference: GenderPreference.everyone,
      );
    final faceDetectionRepository = _FakeFaceDetectionRepository();

    final proSession = ProSession(
      getCurrentSessionUseCase: GetCurrentSessionUseCase(sessionRepository),
      startSessionUseCase: StartSessionUseCase(
        repository: sessionRepository,
        checkSelfieHasFaceUseCase: CheckSelfieHasFaceUseCase(
          faceDetectionRepository,
        ),
      ),
      endSessionUseCase: EndSessionUseCase(sessionRepository),
      checkSelfieHasFaceUseCase: CheckSelfieHasFaceUseCase(
        faceDetectionRepository,
      ),
      stopBeingVisibleUseCase: StopBeingVisibleUseCase(
        _StuckNearbyRepository(),
      ),
    );

    // Lascia finire il caricamento iniziale (_load(), chiamato dal costruttore).
    await Future<void>.delayed(Duration.zero);
    expect(proSession.isOnline, isTrue);

    // Se il bug fosse tornato, questo timeout scadrebbe e il test fallirebbe
    // per "Bad state: Future already completed"/timeout, invece che perché
    // isOnline è ancora true.
    await proSession.end().timeout(const Duration(seconds: 5));

    expect(proSession.isOnline, isFalse);
  });
}
