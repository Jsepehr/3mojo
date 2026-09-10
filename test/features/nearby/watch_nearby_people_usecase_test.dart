import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/nearby/domain/entities/geo_location.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/nearby/domain/repositories/location_repository.dart';
import 'package:threemojo_app/features/nearby/domain/repositories/nearby_repository.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/get_current_location_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/watch_nearby_people_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/watch_position_usecase.dart';
import 'package:threemojo_app/features/session/domain/entities/online_session.dart';
import 'package:threemojo_app/features/session/domain/repositories/session_repository.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';

const _here = GeoLocation(latitude: 45.0, longitude: 9.0);

class _FakeSessionRepository implements SessionRepository {
  _FakeSessionRepository({this.current});

  final OnlineSession? current;

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
  Future<Either<Failure, Unit>> endSession() =>
      throw UnimplementedError('not needed for this test');
}

class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({this.locationResult});

  final Either<Failure, GeoLocation>? locationResult;

  @override
  Future<Either<Failure, GeoLocation>> getCurrentLocation() async =>
      locationResult ?? const Right(_here);

  @override
  Stream<Either<Failure, GeoLocation>> watchPosition() => const Stream.empty();
}

class _FakeNearbyRepository implements NearbyRepository {
  String? lastSessionId;

  @override
  Stream<Either<Failure, List<NearbyPerson>>> watchNearbyPeople(
    GeoLocation location, {
    required String sessionId,
    required String gender,
    required String genderPreference,
    required Uint8List selfieBytes,
  }) {
    lastSessionId = sessionId;
    return const Stream.empty();
  }

  @override
  void updatePosition(GeoLocation location) {}

  @override
  Future<Either<Failure, Unit>> stopBeingVisible(String sessionId) async =>
      const Right(unit);
}

WatchNearbyPeopleUseCase _buildUseCase({
  OnlineSession? session,
  Either<Failure, GeoLocation>? locationResult,
  NearbyRepository? nearbyRepository,
}) {
  final sessionRepository = _FakeSessionRepository(current: session);
  final locationRepository = _FakeLocationRepository(
    locationResult: locationResult,
  );

  return WatchNearbyPeopleUseCase(
    getCurrentSessionUseCase: GetCurrentSessionUseCase(sessionRepository),
    getCurrentLocationUseCase: GetCurrentLocationUseCase(locationRepository),
    watchPositionUseCase: WatchPositionUseCase(locationRepository),
    nearbyRepository: nearbyRepository ?? _FakeNearbyRepository(),
  );
}

void main() {
  group('WatchNearbyPeopleUseCase', () {
    test('fails with a validation error when there is no active session', () async {
      final useCase = _buildUseCase(session: null);

      final result = await useCase().first;

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('propagates a location failure instead of reaching the repository', () async {
      final nearbyRepository = _FakeNearbyRepository();
      final useCase = _buildUseCase(
        session: OnlineSession(
          sessionId: 's1',
          selfiePath: '',
          selfieBytes: Uint8List(0),
          gender: Gender.male,
          genderPreference: GenderPreference.everyone,
        ),
        locationResult: const Left(LocationDisabledFailure('GPS off')),
        nearbyRepository: nearbyRepository,
      );

      final result = await useCase().first;

      expect(result.isLeft(), isTrue);
      expect(nearbyRepository.lastSessionId, isNull);
    });

    test('queries the repository with the current session id', () async {
      final nearbyRepository = _FakeNearbyRepository();
      final useCase = _buildUseCase(
        session: OnlineSession(
          sessionId: 's1',
          selfiePath: '',
          selfieBytes: Uint8List(0),
          gender: Gender.male,
          genderPreference: GenderPreference.everyone,
        ),
        nearbyRepository: nearbyRepository,
      );

      await useCase().drain<void>();

      expect(nearbyRepository.lastSessionId, 's1');
    });
  });
}
