import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/profile/domain/usecases/get_profile_usecase.dart';
import 'package:threemojo_app/features/session/data/datasources/face_detection_local_data_source.dart';
import 'package:threemojo_app/features/session/data/repositories/face_detection_repository_impl.dart';
import 'package:threemojo_app/features/session/domain/usecases/check_selfie_has_face_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/start_session_usecase.dart';

import '../../support/fake_repositories.dart';

final _selfie = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

class _ThrowingFaceDetectionDataSource implements FaceDetectionLocalDataSource {
  @override
  Future<bool> detectFace(Uint8List imageBytes) async =>
      throw PlatformException(code: 'DETECTION_FAILED', message: 'ML Kit');
}

void main() {
  late FakeSessionRepository sessions;
  late FakeProfileRepository profiles;
  late FakeFaceDetectionRepository faces;
  late StartSessionUseCase startSession;

  setUp(() {
    sessions = FakeSessionRepository();
    profiles = FakeProfileRepository(saved: testProfile);
    faces = FakeFaceDetectionRepository();
    startSession = StartSessionUseCase(
      repository: sessions,
      checkSelfieHasFaceUseCase: CheckSelfieHasFaceUseCase(faces),
      getProfileUseCase: GetProfileUseCase(profiles),
    );
  });

  group('StartSessionUseCase', () {
    test('without a selfie: SelfieMissingFailure, nothing else runs', () async {
      final result = await startSession(
        StartSessionParams(selfieBytes: Uint8List(0)),
      );

      expect(result.getLeft().toNullable(), isA<SelfieMissingFailure>());
      expect(faces.checked, isEmpty);
      expect(sessions.current, isNull);
    });

    test('without a profile: ProfileMissingFailure', () async {
      profiles.saved = null;

      final result = await startSession(
        StartSessionParams(selfieBytes: _selfie),
      );

      expect(result.getLeft().toNullable(), isA<ProfileMissingFailure>());
      expect(sessions.current, isNull);
    });

    test('an unreadable profile keeps its own failure', () async {
      profiles.getResult = const Left(CacheFailure('Profile unreadable'));

      final result = await startSession(
        StartSessionParams(selfieBytes: _selfie),
      );

      expect(result.getLeft().toNullable(), isA<CacheFailure>());
      expect(sessions.current, isNull);
    });

    test('a selfie without a face is refused', () async {
      faces.result = const Right(false);

      final result = await startSession(
        StartSessionParams(selfieBytes: _selfie),
      );

      expect(result.getLeft().toNullable(), isA<NoFaceInSelfieFailure>());
      expect(sessions.current, isNull);
    });

    test('goes online with the checked selfie, the profile and the intent of '
        'this session', () async {
      final result = await startSession(
        StartSessionParams(selfieBytes: _selfie, intent: MeetIntent.chat),
      );

      final session = result.getRight().toNullable()!;
      expect(faces.checked.single, _selfie);
      expect(session.selfieBytes, _selfie);
      expect(session.profile, testProfile);
      expect(session.intent, MeetIntent.chat);
      expect(session.sessionId, isNotEmpty);
      expect(sessions.current, session);
    });

    test('every Start gets a brand new session id', () async {
      final first = await startSession(
        StartSessionParams(selfieBytes: _selfie),
      );
      final second = await startSession(
        StartSessionParams(selfieBytes: _selfie),
      );

      expect(
        first.getRight().toNullable()!.sessionId,
        isNot(second.getRight().toNullable()!.sessionId),
      );
    });
  });

  group('CheckSelfieHasFaceUseCase', () {
    test(
      'no bytes: SelfieMissingFailure without asking the detector',
      () async {
        final result = await CheckSelfieHasFaceUseCase(faces)(Uint8List(0));

        expect(result.getLeft().toNullable(), isA<SelfieMissingFailure>());
        expect(faces.checked, isEmpty);
      },
    );

    test('no face: NoFaceInSelfieFailure; a face: ok', () async {
      faces.result = const Right(false);
      expect(
        (await CheckSelfieHasFaceUseCase(faces)(
          _selfie,
        )).getLeft().toNullable(),
        isA<NoFaceInSelfieFailure>(),
      );

      faces.result = const Right(true);
      expect(
        (await CheckSelfieHasFaceUseCase(faces)(_selfie)).isRight(),
        isTrue,
      );
    });

    test('a native channel error becomes FaceCheckUnavailableFailure, never '
        'a raw PlatformException', () async {
      final useCase = CheckSelfieHasFaceUseCase(
        FaceDetectionRepositoryImpl(_ThrowingFaceDetectionDataSource()),
      );

      final failure = (await useCase(_selfie)).getLeft().toNullable();

      expect(failure, isA<FaceCheckUnavailableFailure>());
      expect(failure!.message, isNot(contains('ML Kit')));
    });
  });
}
