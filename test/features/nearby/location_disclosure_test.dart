import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:provider/provider.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/usecases/usecase.dart';
import 'package:threemojo_app/features/nearby/domain/entities/background_location_notice.dart';
import 'package:threemojo_app/features/nearby/domain/entities/geo_location.dart';
import 'package:threemojo_app/features/nearby/domain/entities/location_disclosure.dart';
import 'package:threemojo_app/features/nearby/domain/entities/location_permission_status.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/nearby/domain/repositories/location_repository.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/get_location_disclosure_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/open_app_settings_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/open_location_settings_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/request_location_permission_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/watch_nearby_people_usecase.dart';
import 'package:threemojo_app/features/nearby/presentation/pages/ui_location_disclosure.dart';
import 'package:threemojo_app/features/nearby/presentation/providers/pro_nearby.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import '../../support/fake_repositories.dart';

/// Permesso di posizione pilotabile: [status] è ciò che il sistema
/// risponde a un controllo, [afterRequest] ciò che risulta dopo la
/// richiesta di sistema (che conta in [requestCalls]).
class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({
    this.status = const Right(LocationPermissionStatus.denied),
    this.afterRequest = LocationPermissionStatus.granted,
    this.keepsTrackingInBackground = true,
  });

  Either<Failure, LocationPermissionStatus> status;
  LocationPermissionStatus afterRequest;
  int requestCalls = 0;
  int openAppSettingsCalls = 0;

  @override
  final bool keepsTrackingInBackground;

  @override
  Future<Either<Failure, LocationPermissionStatus>> checkPermission() async =>
      status;

  @override
  Future<Either<Failure, LocationPermissionStatus>> requestPermission() async {
    requestCalls++;
    status = Right(afterRequest);
    return Right(afterRequest);
  }

  @override
  Future<Either<Failure, GeoLocation>> getCurrentLocation() =>
      throw UnimplementedError('not needed for this test');

  @override
  Stream<Either<Failure, GeoLocation>> watchPosition({
    required BackgroundLocationNotice notice,
  }) => const Stream.empty();

  @override
  Future<Either<Failure, Unit>> openLocationSettings() async =>
      const Right(unit);

  @override
  Future<Either<Failure, Unit>> openAppSettings() async {
    openAppSettingsCalls++;
    return const Right(unit);
  }
}

class _IdleWatchNearbyPeopleUseCase implements WatchNearbyPeopleUseCase {
  @override
  Stream<Either<Failure, List<NearbyPerson>>> call({
    BackgroundLocationNotice? backgroundNotice,
  }) => const Stream.empty();
}

void main() {
  group('GetLocationDisclosureUseCase', () {
    test('no disclosure once the permission is granted', () async {
      final repository = _FakeLocationRepository(
        status: const Right(LocationPermissionStatus.granted),
      );

      final result = await GetLocationDisclosureUseCase(repository)(
        const NoParams(),
      );

      expect(result, const Right<Failure, LocationDisclosure?>(null));
    });

    test('shown before the first request and every time the permission is '
        'still missing (denied or denied forever)', () async {
      for (final status in [
        LocationPermissionStatus.denied,
        LocationPermissionStatus.deniedForever,
      ]) {
        final repository = _FakeLocationRepository(status: Right(status));

        final result = await GetLocationDisclosureUseCase(repository)(
          const NoParams(),
        );

        expect(result.getRight().toNullable(), isNotNull, reason: '$status');
      }
    });

    test('says whether the location keeps being used in the background, '
        'as the platform really does', () async {
      final android = _FakeLocationRepository(keepsTrackingInBackground: true);
      final ios = _FakeLocationRepository(keepsTrackingInBackground: false);

      final onAndroid = await GetLocationDisclosureUseCase(android)(
        const NoParams(),
      );
      final onIos = await GetLocationDisclosureUseCase(ios)(const NoParams());

      expect(
        onAndroid.getRight().toNullable(),
        const LocationDisclosure(continuesInBackground: true),
      );
      expect(
        onIos.getRight().toNullable(),
        const LocationDisclosure(continuesInBackground: false),
      );
    });

    test('when the status cannot be read, the disclosure is shown anyway, '
        'and nothing is ever requested', () async {
      final repository = _FakeLocationRepository(
        status: const Left(UnexpectedFailure('no plugin')),
      );

      final result = await GetLocationDisclosureUseCase(repository)(
        const NoParams(),
      );

      expect(result.getRight().toNullable(), isNotNull);
      expect(repository.requestCalls, 0);
    });
  });

  group('RequestLocationPermissionUseCase', () {
    test('granted: the Start can go on', () async {
      final repository = _FakeLocationRepository();

      final result = await RequestLocationPermissionUseCase(repository)(
        const NoParams(),
      );

      expect(result.isRight(), isTrue);
      expect(repository.requestCalls, 1);
    });

    test('not granted: LocationPermissionFailure, no going online', () async {
      for (final status in [
        LocationPermissionStatus.denied,
        LocationPermissionStatus.deniedForever,
      ]) {
        final repository = _FakeLocationRepository(afterRequest: status);

        final result = await RequestLocationPermissionUseCase(repository)(
          const NoParams(),
        );

        expect(result.getLeft().toNullable(), isA<LocationPermissionFailure>());
      }
    });
  });

  group('showLocationDisclosureIfNeeded', () {
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    /// Una pagina con un bottone che fa ciò che fa "Start" sulla home:
    /// chiede l'avviso e ricorda l'esito in [outcomes].
    Future<List<bool>> pump(
      WidgetTester tester,
      _FakeLocationRepository repository,
    ) async {
      final outcomes = <bool>[];
      final proNearby = ProNearby(
        watchSessionUseCase: WatchSessionUseCase(FakeSessionRepository()),
        watchNearbyPeopleUseCase: _IdleWatchNearbyPeopleUseCase(),
        openLocationSettingsUseCase: OpenLocationSettingsUseCase(repository),
        openAppSettingsUseCase: OpenAppSettingsUseCase(repository),
        getLocationDisclosureUseCase: GetLocationDisclosureUseCase(repository),
        requestLocationPermissionUseCase: RequestLocationPermissionUseCase(
          repository,
        ),
      );
      addTearDown(proNearby.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: proNearby,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => outcomes.add(
                    await showLocationDisclosureIfNeeded(context),
                  ),
                  child: const Text('Start'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      return outcomes;
    }

    testWidgets('before the first request: the full-screen notice, then '
        '"Continue" asks the system permission and the Start goes on', (
      tester,
    ) async {
      final repository = _FakeLocationRepository();
      final outcomes = await pump(tester, repository);

      expect(find.byType(UiLocationDisclosure), findsOneWidget);
      expect(repository.requestCalls, 0, reason: 'never before the notice');
      expect(find.text(l10n.location_disclosure_use), findsOneWidget);
      expect(find.text(l10n.location_disclosure_offline), findsOneWidget);

      await tester.tap(find.text(l10n.location_disclosure_continue));
      await tester.pumpAndSettle();

      expect(repository.requestCalls, 1);
      expect(find.byType(UiLocationDisclosure), findsNothing);
      expect(outcomes, [true]);
    });

    testWidgets('"Not now": nothing is asked and you stay offline', (
      tester,
    ) async {
      final repository = _FakeLocationRepository();
      final outcomes = await pump(tester, repository);

      await tester.tap(find.text(l10n.location_disclosure_not_now));
      await tester.pumpAndSettle();

      expect(repository.requestCalls, 0);
      expect(find.byType(UiLocationDisclosure), findsNothing);
      expect(outcomes, [false]);
    });

    testWidgets('already granted: no notice, no request, the Start goes on', (
      tester,
    ) async {
      final repository = _FakeLocationRepository(
        status: const Right(LocationPermissionStatus.granted),
      );
      final outcomes = await pump(tester, repository);

      expect(find.byType(UiLocationDisclosure), findsNothing);
      expect(repository.requestCalls, 0);
      expect(outcomes, [true]);
    });

    testWidgets('permission refused after "Continue": you stay offline and '
        'a message leads to the settings', (tester) async {
      final repository = _FakeLocationRepository(
        afterRequest: LocationPermissionStatus.deniedForever,
      );
      final outcomes = await pump(tester, repository);

      await tester.tap(find.text(l10n.location_disclosure_continue));
      await tester.pumpAndSettle();

      expect(outcomes, [false]);
      expect(
        find.text(l10n.location_permission_needed_to_go_online),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.open_settings));
      await tester.pumpAndSettle();
      expect(repository.openAppSettingsCalls, 1);
    });

    testWidgets('the texts are true per platform: background with a '
        'notification on Android, only on screen on iPhone', (tester) async {
      await pump(
        tester,
        _FakeLocationRepository(keepsTrackingInBackground: true),
      );
      expect(find.text(l10n.location_disclosure_background), findsOneWidget);
      expect(find.text(l10n.location_disclosure_foreground_only), findsNothing);
      await tester.tap(find.text(l10n.location_disclosure_not_now));
      await tester.pumpAndSettle();

      await pump(
        tester,
        _FakeLocationRepository(keepsTrackingInBackground: false),
      );
      expect(find.text(l10n.location_disclosure_background), findsNothing);
      expect(
        find.text(l10n.location_disclosure_foreground_only),
        findsOneWidget,
      );
    });
  });
}
