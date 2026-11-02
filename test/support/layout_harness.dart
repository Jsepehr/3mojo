import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'package:threemojo_app/app.dart';
import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/theme/app_theme.dart';
import 'package:threemojo_app/features/demo/domain/usecases/check_demo_available_usecase.dart';
import 'package:threemojo_app/features/demo/presentation/providers/pro_demo.dart';
import 'package:threemojo_app/features/nearby/domain/entities/background_location_notice.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/nearby/domain/entities/location_permission_status.dart';
import 'package:threemojo_app/features/nearby/domain/repositories/location_repository.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/get_location_disclosure_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/open_app_settings_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/open_location_settings_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/request_location_permission_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/watch_nearby_people_usecase.dart';
import 'package:threemojo_app/features/nearby/presentation/providers/pro_nearby.dart';
import 'package:threemojo_app/features/profile/domain/usecases/delete_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/get_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/save_profile_usecase.dart';
import 'package:threemojo_app/features/profile/presentation/providers/pro_profile.dart';
import 'package:threemojo_app/features/safety/domain/usecases/block_person_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/report_person_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/watch_blocked_people_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/watch_safety_rejections_usecase.dart';
import 'package:threemojo_app/features/safety/presentation/providers/pro_safety.dart';
import 'package:threemojo_app/features/session/domain/repositories/selfie_repository.dart';
import 'package:threemojo_app/features/session/domain/usecases/check_connection_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/check_selfie_has_face_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/end_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/flip_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/start_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/take_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/update_profile_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_connection_status_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_server_session_restarts_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/withdraw_profile_usecase.dart';
import 'package:threemojo_app/features/session/presentation/providers/pro_connection.dart';
import 'package:threemojo_app/features/session/presentation/providers/pro_session.dart';
import 'package:threemojo_app/features/settings/domain/entities/app_language.dart';
import 'package:threemojo_app/features/settings/domain/entities/app_theme_mode.dart';
import 'package:threemojo_app/features/settings/domain/repositories/settings_repository.dart';
import 'package:threemojo_app/features/settings/domain/usecases/get_fake_mode_usecase.dart';
import 'package:threemojo_app/features/settings/domain/usecases/get_language_usecase.dart';
import 'package:threemojo_app/features/settings/domain/usecases/get_theme_mode_usecase.dart';
import 'package:threemojo_app/features/settings/domain/usecases/set_fake_mode_usecase.dart';
import 'package:threemojo_app/features/settings/domain/usecases/set_language_usecase.dart';
import 'package:threemojo_app/features/settings/domain/usecases/set_theme_mode_usecase.dart';
import 'package:threemojo_app/features/settings/presentation/providers/pro_settings.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import 'build_providers.dart';
import 'fake_paywall.dart';
import 'fake_repositories.dart';
import 'fake_safety.dart';

/// Una superficie di prova: telefono stretto (360 x 740 dp, quello che ha
/// fatto uscire gli overflow), lingua e scala del testo. Con [name] si
/// distinguono i test.
class LayoutCase {
  const LayoutCase({
    required this.size,
    required this.textScale,
    required this.language,
  });

  final Size size;
  final double textScale;
  final AppLanguage language;

  Locale get locale => Locale(language.languageCode!);

  String get name =>
      '${size.width.toInt()}x${size.height.toInt()} '
      'text ${textScale}x ${language.languageCode}';
}

/// Le combinazioni controllate da ogni pagina: 360 x 740 a testo 1.0 e 2.0,
/// in inglese e in arabo (RTL); più l'orizzontale (740 x 360), che su
/// tablet Android 16+ l'OS può imporre anche con `screenOrientation`.
const layoutCases = <LayoutCase>[
  LayoutCase(
    size: Size(360, 740),
    textScale: 1.0,
    language: AppLanguage.english,
  ),
  LayoutCase(
    size: Size(360, 740),
    textScale: 2.0,
    language: AppLanguage.english,
  ),
  LayoutCase(
    size: Size(360, 740),
    textScale: 1.0,
    language: AppLanguage.arabic,
  ),
  LayoutCase(
    size: Size(360, 740),
    textScale: 2.0,
    language: AppLanguage.arabic,
  ),
  LayoutCase(
    size: Size(740, 360),
    textScale: 1.0,
    language: AppLanguage.english,
  ),
];

bool _fontsLoaded = false;

/// Carica Manrope (il font dell'app): senza, i test usano un carattere
/// largo un em per lettera e gli overflow sarebbero falsi.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  final loader = FontLoader(AppTheme.fontFamily);
  for (final file in const [
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
  ]) {
    final bytes = File(
      'assets/fonts/manrope/Manrope-$file.ttf',
    ).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  _fontsLoaded = true;
}

/// Imposta superficie (1 pixel logico = 1 fisico) e scala del testo; si
/// ripristinano da soli a fine test. Un overflow qui fa fallire il test
/// (`FlutterError` "A RenderFlex overflowed").
void applyLayoutCase(WidgetTester tester, LayoutCase layout) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = layout.size;
  tester.platformDispatcher.textScaleFactorTestValue = layout.textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Una pagina sola dentro un `MaterialApp` col tema dell'app, nella lingua
/// del caso.
Widget layoutApp(LayoutCase layout, Widget home) => MaterialApp(
  theme: AppTheme.light,
  locale: layout.locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// Fa scorrere il tempo a piccoli passi (senza `pumpAndSettle`: gli
/// indicatori animati non finirebbero mai).
Future<void> advance(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 500),
]) async {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    await tester.pump(step);
    elapsed += step;
  }
}

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

class _Settings implements SettingsRepository {
  _Settings(this.language);

  final AppLanguage language;

  @override
  Future<Either<Failure, bool>> getFakeMode() async => const Right(false);

  @override
  Future<Either<Failure, Unit>> setFakeMode(bool enabled) async =>
      const Right(unit);

  @override
  Future<Either<Failure, AppLanguage>> getLanguage() async => Right(language);

  @override
  Future<Either<Failure, Unit>> setLanguage(AppLanguage language) async =>
      const Right(unit);

  @override
  Future<Either<Failure, AppThemeMode>> getThemeMode() async =>
      const Right(AppThemeMode.light);

  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode themeMode) async =>
      const Right(unit);
}

class _Selfies implements SelfieRepository {
  @override
  Future<Either<Failure, Uint8List?>> takeSelfie() async =>
      Right(Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4))));

  @override
  Future<Either<Failure, Uint8List>> flipHorizontally(Uint8List bytes) async =>
      Right(bytes);

  @override
  Future<Either<Failure, Unit>> discardLeftoverFiles() async =>
      const Right(unit);
}

/// Permesso non ancora concesso: così "Start" mostra l'avviso in evidenza;
/// dopo "Continua" la richiesta di sistema lo concede.
class _Location implements LocationRepository {
  @override
  Future<Either<Failure, LocationPermissionStatus>> checkPermission() async =>
      const Right(LocationPermissionStatus.denied);

  @override
  Future<Either<Failure, LocationPermissionStatus>> requestPermission() async =>
      const Right(LocationPermissionStatus.granted);

  @override
  bool get keepsTrackingInBackground => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoNearby implements WatchNearbyPeopleUseCase {
  @override
  Stream<Either<Failure, List<NearbyPerson>>> call({
    required BackgroundLocationNotice backgroundNotice,
  }) => const Stream.empty();
}

/// L'app intera (`RaenApp`) su repository finti, nella lingua del caso:
/// serve per le pagine che si raggiungono solo navigando (home offline,
/// demo online con il banner del paywall, richieste, tendina, chat).
class LayoutWorld {
  LayoutWorld(this.language) {
    wakelockPlusPlatformInstance = _NoWakelock();
  }

  final AppLanguage language;
  final sessions = FakeSessionRepository();
  final profiles = FakeProfileRepository(saved: testProfile);
  final faces = FakeFaceDetectionRepository();
  final connection = FakeConnectionRepository();
  final paywall = FakePaywallServer();
  final encounters = FakeEncounterRepository();
  final chat = FakeChatRepository();
  final safety = buildSafety();

  Widget build() {
    final settings = _Settings(language);
    final location = _Location();
    final selfies = _Selfies();
    final endSession = EndSessionUseCase(repository: sessions);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ProSettings(
            getLanguageUseCase: GetLanguageUseCase(settings),
            setLanguageUseCase: SetLanguageUseCase(settings),
            getThemeModeUseCase: GetThemeModeUseCase(settings),
            setThemeModeUseCase: SetThemeModeUseCase(settings),
            getFakeModeUseCase: GetFakeModeUseCase(
              settings,
              isAvailable: false,
            ),
            setFakeModeUseCase: SetFakeModeUseCase(
              settings,
              isAvailable: false,
            ),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ProProfile(
            getProfileUseCase: GetProfileUseCase(profiles),
            saveProfileUseCase: SaveProfileUseCase(profiles),
            updateProfileUseCase: UpdateProfileUseCase(
              getCurrentSessionUseCase: GetCurrentSessionUseCase(sessions),
              endSessionUseCase: endSession,
              saveProfileUseCase: SaveProfileUseCase(profiles),
            ),
            withdrawProfileUseCase: WithdrawProfileUseCase(
              getCurrentSessionUseCase: GetCurrentSessionUseCase(sessions),
              endSessionUseCase: endSession,
              deleteProfileUseCase: DeleteProfileUseCase(profiles),
            ),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSession(
            watchSessionUseCase: WatchSessionUseCase(sessions),
            startSessionUseCase: StartSessionUseCase(
              repository: sessions,
              checkSelfieHasFaceUseCase: CheckSelfieHasFaceUseCase(faces),
              getProfileUseCase: GetProfileUseCase(profiles),
            ),
            endSessionUseCase: endSession,
            checkSelfieHasFaceUseCase: CheckSelfieHasFaceUseCase(faces),
            takeSelfieUseCase: TakeSelfieUseCase(selfies),
            flipSelfieUseCase: FlipSelfieUseCase(selfies),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ProConnection(
            watchConnectionStatusUseCase: WatchConnectionStatusUseCase(
              connection,
            ),
            watchServerSessionRestartsUseCase:
                WatchServerSessionRestartsUseCase(connection),
            checkConnectionUseCase: CheckConnectionUseCase(connection),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ProNearby(
            watchSessionUseCase: WatchSessionUseCase(sessions),
            watchNearbyPeopleUseCase: _NoNearby(),
            openLocationSettingsUseCase: OpenLocationSettingsUseCase(location),
            openAppSettingsUseCase: OpenAppSettingsUseCase(location),
            getLocationDisclosureUseCase: GetLocationDisclosureUseCase(
              location,
            ),
            requestLocationPermissionUseCase: RequestLocationPermissionUseCase(
              location,
            ),
            watchBlockedPeopleUseCase: WatchBlockedPeopleUseCase(
              safety.repository,
            ),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => buildProPaywall(sessions: sessions, paywall: paywall),
        ),
        ChangeNotifierProvider(
          create: (_) => buildProEncounters(
            sessions: sessions,
            encounters: encounters,
            chat: chat,
            connection: connection,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ProSafety(
            watchSessionUseCase: WatchSessionUseCase(sessions),
            blockPersonUseCase: BlockPersonUseCase(safety.repository),
            reportPersonUseCase: ReportPersonUseCase(
              safety.repository,
              BlockPersonUseCase(safety.repository),
            ),
            watchSafetyRejectionsUseCase: WatchSafetyRejectionsUseCase(
              getCurrentSessionUseCase: GetCurrentSessionUseCase(sessions),
              repository: safety.repository,
            ),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => buildProChat(sessions: sessions, chat: chat),
        ),
        ChangeNotifierProvider(
          create: (_) => ProDemo(
            checkDemoAvailableUseCase: CheckDemoAvailableUseCase(
              GetCurrentSessionUseCase(sessions),
            ),
          ),
        ),
      ],
      child: const RaenApp(),
    );
  }
}
