import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/nearby/domain/entities/background_location_notice.dart';
import 'package:threemojo_app/features/nearby/domain/entities/geo_location.dart';
import 'package:threemojo_app/features/nearby/domain/entities/location_permission_status.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/nearby/domain/repositories/location_repository.dart';
import 'package:threemojo_app/features/nearby/domain/repositories/nearby_repository.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/get_current_location_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/watch_nearby_people_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/watch_position_usecase.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/session/domain/entities/online_session.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';

import '../../support/fake_repositories.dart';

const _here = GeoLocation(latitude: 45.0, longitude: 9.0);

class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({this.locationResult, this.pendingLocation});

  final Either<Failure, GeoLocation>? locationResult;

  /// Se c'è, il GPS "ci mette un po'": risponde quando il test lo completa.
  final Completer<Either<Failure, GeoLocation>>? pendingLocation;

  @override
  Future<Either<Failure, GeoLocation>> getCurrentLocation() async =>
      pendingLocation?.future ?? locationResult ?? const Right(_here);

  @override
  Stream<Either<Failure, GeoLocation>> watchPosition({
    BackgroundLocationNotice? notice,
  }) {
    notices.add(notice);
    return const Stream.empty();
  }

  final notices = <BackgroundLocationNotice?>[];

  @override
  Future<Either<Failure, Unit>> openLocationSettings() async =>
      const Right(unit);

  @override
  Future<Either<Failure, Unit>> openAppSettings() async => const Right(unit);

  @override
  Future<Either<Failure, LocationPermissionStatus>> checkPermission() async =>
      const Right(LocationPermissionStatus.granted);

  @override
  Future<Either<Failure, LocationPermissionStatus>> requestPermission() async =>
      const Right(LocationPermissionStatus.granted);

  @override
  bool get keepsTrackingInBackground => true;
}

class _FakeNearbyRepository implements NearbyRepository {
  String? lastSessionId;

  @override
  Stream<Either<Failure, List<NearbyPerson>>> watchNearbyPeople(
    GeoLocation location, {
    required String sessionId,
    required Profile profile,
    MeetIntent? intent,
    required Uint8List selfieBytes,
  }) {
    lastSessionId = sessionId;
    return const Stream.empty();
  }

  @override
  void updatePosition(GeoLocation location) {}

  @override
  Future<Either<Failure, Unit>> stopBeingVisible() async => const Right(unit);
}

WatchNearbyPeopleUseCase _buildUseCase({
  OnlineSession? session,
  FakeSessionRepository? sessionRepository,
  Either<Failure, GeoLocation>? locationResult,
  Completer<Either<Failure, GeoLocation>>? pendingLocation,
  NearbyRepository? nearbyRepository,
  _FakeLocationRepository? locationRepository,
}) {
  sessionRepository ??= FakeSessionRepository(current: session);
  locationRepository ??= _FakeLocationRepository(
    locationResult: locationResult,
    pendingLocation: pendingLocation,
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
    test(
      'fails with a not-online error when there is no active session',
      () async {
        final useCase = _buildUseCase(session: null);

        final result = await useCase(backgroundNotice: _notice).first;

        expect(result.isLeft(), isTrue);
        expect(result.getLeft().toNullable(), isA<NotOnlineFailure>());
      },
    );

    test(
      'propagates a location failure instead of reaching the repository',
      () async {
        final nearbyRepository = _FakeNearbyRepository();
        final useCase = _buildUseCase(
          session: OnlineSession(
            sessionId: 's1',
            selfieBytes: Uint8List(0),
            profile: _profile,
          ),
          locationResult: const Left(LocationDisabledFailure('GPS off')),
          nearbyRepository: nearbyRepository,
        );

        final result = await useCase(backgroundNotice: _notice).first;

        expect(result.isLeft(), isTrue);
        expect(nearbyRepository.lastSessionId, isNull);
      },
    );

    test('queries the repository with the current session id', () async {
      final nearbyRepository = _FakeNearbyRepository();
      final useCase = _buildUseCase(
        session: OnlineSession(
          sessionId: 's1',
          selfieBytes: Uint8List(0),
          profile: _profile,
        ),
        nearbyRepository: nearbyRepository,
      );

      await useCase(backgroundNotice: _notice).drain<void>();

      expect(nearbyRepository.lastSessionId, 's1');
    });

    test('End while waiting for the GPS: never connects with the old '
        'session (no ghost presence)', () async {
      final sessions = FakeSessionRepository(current: testSession('s1'));
      final pendingLocation = Completer<Either<Failure, GeoLocation>>();
      final nearbyRepository = _FakeNearbyRepository();
      final results = <Either<Failure, List<NearbyPerson>>>[];
      final useCase = _buildUseCase(
        sessionRepository: sessions,
        pendingLocation: pendingLocation,
        nearbyRepository: nearbyRepository,
      );

      final done = useCase(
        backgroundNotice: _notice,
      ).listen(results.add).asFuture<void>();
      await Future<void>.delayed(Duration.zero);
      sessions.end();
      pendingLocation.complete(const Right(_here));
      await done;

      expect(nearbyRepository.lastSessionId, isNull);
      expect(results.single.getLeft().toNullable(), isA<NotOnlineFailure>());
    });

    test('a new Start while waiting for the GPS does not reuse the old '
        'session', () async {
      final sessions = FakeSessionRepository(current: testSession('s1'));
      final pendingLocation = Completer<Either<Failure, GeoLocation>>();
      final nearbyRepository = _FakeNearbyRepository();
      final useCase = _buildUseCase(
        sessionRepository: sessions,
        pendingLocation: pendingLocation,
        nearbyRepository: nearbyRepository,
      );

      final done = useCase(backgroundNotice: _notice).drain<void>();
      await Future<void>.delayed(Duration.zero);
      sessions
        ..end()
        ..start(testSession('s2'));
      pendingLocation.complete(const Right(_here));
      await done;

      expect(nearbyRepository.lastSessionId, isNull);
    });

    test('hands the translated background notice down to the position '
        'watch', () async {
      const notice = BackgroundLocationNotice(
        title: 'Raen ist online',
        body: 'Leute in deiner Nähe sehen dich',
        channelName: 'Online-Präsenz',
      );
      final locationRepository = _FakeLocationRepository();
      final useCase = _buildUseCase(
        session: testSession('s1'),
        locationRepository: locationRepository,
      );

      await useCase(backgroundNotice: notice).drain<void>();

      expect(locationRepository.notices, [notice]);
    });
  });
}

const _notice = BackgroundLocationNotice(
  title: 'Raen is online',
  body: 'People nearby can see you',
  channelName: 'Online presence',
);

const _profile = Profile(
  gender: Gender.male,
  lookingFor: Profile.searchableGenders,
  isAdultConfirmed: true,
  acceptedSensitiveConsentVersion: Profile.currentSensitiveConsentVersion,
);
