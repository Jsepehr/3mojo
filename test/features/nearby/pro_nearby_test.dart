import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/nearby/domain/entities/background_location_notice.dart';
import 'package:threemojo_app/features/nearby/domain/entities/geo_location.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/nearby/domain/repositories/location_repository.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/open_app_settings_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/open_location_settings_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/watch_nearby_people_usecase.dart';
import 'package:threemojo_app/features/nearby/presentation/providers/pro_nearby.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';

import '../../support/fake_repositories.dart';

/// Ogni chiamata apre un nuovo stream controllabile dal test — come una
/// nuova connessione al server.
class _FakeWatchNearbyPeopleUseCase implements WatchNearbyPeopleUseCase {
  final controllers = <StreamController<Either<Failure, List<NearbyPerson>>>>[];
  final notices = <BackgroundLocationNotice?>[];

  StreamController<Either<Failure, List<NearbyPerson>>> get last =>
      controllers.last;

  @override
  Stream<Either<Failure, List<NearbyPerson>>> call({
    BackgroundLocationNotice? backgroundNotice,
  }) {
    notices.add(backgroundNotice);
    final controller = StreamController<Either<Failure, List<NearbyPerson>>>();
    controllers.add(controller);
    return controller.stream;
  }
}

class _FakeLocationRepository implements LocationRepository {
  int openLocationSettingsCalls = 0;
  int openAppSettingsCalls = 0;

  @override
  Future<Either<Failure, GeoLocation>> getCurrentLocation() =>
      throw UnimplementedError('not needed for this test');

  @override
  Stream<Either<Failure, GeoLocation>> watchPosition({
    BackgroundLocationNotice? notice,
  }) => const Stream.empty();

  @override
  Future<Either<Failure, Unit>> openLocationSettings() async {
    openLocationSettingsCalls++;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> openAppSettings() async {
    openAppSettingsCalls++;
    return const Right(unit);
  }
}

const _notice = BackgroundLocationNotice(
  title: 'Raen is online',
  body: 'People nearby can see you',
  channelName: 'Online presence',
);

void main() {
  late FakeSessionRepository sessions;
  late _FakeWatchNearbyPeopleUseCase watch;
  late _FakeLocationRepository locationRepository;
  late ProNearby proNearby;

  setUp(() async {
    sessions = FakeSessionRepository(current: testSession('s1'));
    watch = _FakeWatchNearbyPeopleUseCase();
    locationRepository = _FakeLocationRepository();
    proNearby = ProNearby(
      watchSessionUseCase: WatchSessionUseCase(sessions),
      watchNearbyPeopleUseCase: watch,
      openLocationSettingsUseCase: OpenLocationSettingsUseCase(
        locationRepository,
      ),
      openAppSettingsUseCase: OpenAppSettingsUseCase(locationRepository),
    )..setBackgroundLocationNotice(_notice);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => proNearby.dispose());

  test(
    'exposes the failure itself, so the UI can pick texts by type',
    () async {
      watch.last.add(const Left(ConnectionFailure('socket closed')));
      await Future<void>.delayed(Duration.zero);

      expect(proNearby.failure, isA<ConnectionFailure>());
      expect(proNearby.isLoading, isFalse);
    },
  );

  test('treats "not online yet" as still loading, not as an error', () async {
    watch.last.add(const Left(NotOnlineFailure('No active session')));
    await Future<void>.delayed(Duration.zero);

    expect(proNearby.failure, isNull);
    expect(proNearby.isLoading, isTrue);
  });

  test('a new list clears the previous failure', () async {
    watch.last.add(const Left(LocationDisabledFailure('GPS off')));
    await Future<void>.delayed(Duration.zero);
    watch.last.add(const Right([]));
    await Future<void>.delayed(Duration.zero);

    expect(proNearby.failure, isNull);
    expect(proNearby.isLoading, isFalse);
  });

  test('a connection drop keeps the list already on screen', () async {
    const person = NearbyPerson(id: 'p1', meetingChance: MeetingChance.low);
    watch.last.add(const Right([person]));
    await Future<void>.delayed(Duration.zero);

    watch.last.add(const Left(ConnectionFailure('socket closed')));
    await Future<void>.delayed(Duration.zero);

    expect(proNearby.people, [person]);
    expect(proNearby.failure, isNull);
  });

  test(
    'End stops listening and forgets the list; Start listens again',
    () async {
      watch.last.add(
        const Right([NearbyPerson(id: 'p1', meetingChance: MeetingChance.low)]),
      );
      await Future<void>.delayed(Duration.zero);
      final firstStream = watch.last;

      sessions.end();
      await Future<void>.delayed(Duration.zero);

      expect(proNearby.people, isEmpty);
      expect(firstStream.hasListener, isFalse);
      expect(watch.controllers, hasLength(1));

      sessions.start(testSession('s2'));
      await Future<void>.delayed(Duration.zero);

      expect(watch.controllers, hasLength(2));
    },
  );

  test('does nothing while offline, not even retry', () async {
    sessions.end();
    await Future<void>.delayed(Duration.zero);

    proNearby.retry();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(watch.controllers, hasLength(1));
    expect(proNearby.isRetrying, isFalse);
  });

  testWidgets('retry reconnects right away and shows a short busy state', (
    tester,
  ) async {
    watch.last.add(const Left(ConnectionFailure('socket closed')));
    await tester.pump();
    expect(watch.controllers, hasLength(1));

    proNearby.retry();

    expect(watch.controllers, hasLength(2));
    expect(proNearby.isRetrying, isTrue);

    await tester.pump(const Duration(seconds: 1));
    expect(proNearby.isRetrying, isFalse);
  });

  test('opens the right system settings', () async {
    await proNearby.openLocationSettings();
    await proNearby.openAppSettings();

    expect(locationRepository.openLocationSettingsCalls, 1);
    expect(locationRepository.openAppSettingsCalls, 1);
  });

  test('the translated background notice set by the UI reaches the next '
      'listening', () async {
    const notice = BackgroundLocationNotice(
      title: 'Raen è online',
      body: 'Stai comparendo a chi ti è vicino',
      channelName: 'Presenza online',
    );
    sessions.end();
    await Future<void>.delayed(Duration.zero);

    proNearby.setBackgroundLocationNotice(notice);
    sessions.start(testSession('s2'));
    await Future<void>.delayed(Duration.zero);

    expect(watch.notices.last, notice);
  });

  test(
    'without the translated notice the listening waits (no fallback '
    'texts in the data layer), and starts as soon as the UI sets it',
    () async {
      final waiting = ProNearby(
        watchSessionUseCase: WatchSessionUseCase(sessions),
        watchNearbyPeopleUseCase: watch,
        openLocationSettingsUseCase: OpenLocationSettingsUseCase(
          locationRepository,
        ),
        openAppSettingsUseCase: OpenAppSettingsUseCase(locationRepository),
      );
      addTearDown(waiting.dispose);
      final callsBefore = watch.notices.length;
      await Future<void>.delayed(Duration.zero);
      expect(watch.notices.length, callsBefore);
      expect(waiting.isLoading, isTrue);

      waiting.setBackgroundLocationNotice(_notice);

      expect(watch.notices.length, callsBefore + 1);
      expect(watch.notices.last, _notice);
    },
  );

  test('a selfie that could not be prepared stays on screen like a '
      'rejected one', () async {
    watch.last.add(const Left(SelfieNotUsableFailure()));
    await Future<void>.delayed(Duration.zero);
    watch.last.add(const Right([]));
    await Future<void>.delayed(Duration.zero);

    expect(proNearby.failure, isA<SelfieNotUsableFailure>());
  });

  test('a selfie rejected by the server stays on screen, even if a list '
      'arrives later; a new session forgets it', () async {
    watch.last.add(const Left(SelfieRejectedByServerFailure()));
    await Future<void>.delayed(Duration.zero);
    watch.last.add(const Right([]));
    await Future<void>.delayed(Duration.zero);

    expect(proNearby.failure, isA<SelfieRejectedByServerFailure>());

    sessions.end();
    sessions.start(testSession('s2'));
    await Future<void>.delayed(Duration.zero);
    expect(proNearby.failure, isNull);
  });

  test('"too many Starts" is not replaced by the connection drop that '
      'follows it', () async {
    watch.last.add(const Left(TooManyStartsFailure()));
    await Future<void>.delayed(Duration.zero);
    watch.last.add(const Left(ConnectionFailure('socket closed')));
    await Future<void>.delayed(Duration.zero);

    expect(proNearby.failure, isA<TooManyStartsFailure>());

    // Quando il server accetta di nuovo, la lista lo sostituisce.
    watch.last.add(const Right([]));
    await Future<void>.delayed(Duration.zero);
    expect(proNearby.failure, isNull);
  });
}
