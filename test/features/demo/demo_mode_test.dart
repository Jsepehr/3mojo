import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'package:threemojo_app/app.dart';
import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/network/realtime_connection.dart';
import 'package:threemojo_app/core/usecases/usecase.dart';
import 'package:threemojo_app/core/utils/illustrated_avatar.dart';
import 'package:threemojo_app/core/widgets/cmp_demo_badge.dart';
import 'package:threemojo_app/features/demo/domain/usecases/check_demo_available_usecase.dart';
import 'package:threemojo_app/features/demo/domain/usecases/start_demo_session_usecase.dart';
import 'package:threemojo_app/features/demo/presentation/providers/pro_demo.dart';
import 'package:threemojo_app/features/encounters/presentation/pages/ui_active_match.dart';
import 'package:threemojo_app/features/encounters/presentation/widgets/cmp_incoming_request_tile.dart';
import 'package:threemojo_app/features/nearby/domain/entities/background_location_notice.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/nearby/domain/repositories/location_repository.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/get_location_disclosure_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/open_app_settings_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/open_location_settings_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/request_location_permission_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/watch_nearby_people_usecase.dart';
import 'package:threemojo_app/features/nearby/presentation/providers/pro_nearby.dart';
import 'package:threemojo_app/features/nearby/presentation/widgets/cmp_nearby_person_tile.dart';
import 'package:threemojo_app/features/paywall/data/datasources/store_billing_data_source.dart';
import 'package:threemojo_app/features/paywall/data/datasources/store_billing_data_source_fake_impl.dart';
import 'package:threemojo_app/features/paywall/domain/entities/store_checkout.dart';
import 'package:threemojo_app/features/paywall/domain/entities/store_purchase.dart';
import 'package:threemojo_app/features/paywall/domain/entities/unlock_offer.dart';
import 'package:threemojo_app/features/paywall/presentation/providers/pro_paywall.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/profile/domain/usecases/delete_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/get_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/save_profile_usecase.dart';
import 'package:threemojo_app/features/profile/presentation/providers/pro_profile.dart';
import 'package:threemojo_app/features/safety/domain/usecases/block_person_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/report_person_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/watch_blocked_people_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/watch_safety_rejections_usecase.dart';
import 'package:threemojo_app/features/safety/presentation/providers/pro_safety.dart';
import 'package:threemojo_app/features/session/data/datasources/selfie_local_data_source_fake_impl.dart';
import 'package:threemojo_app/features/session/data/repositories/selfie_repository_impl.dart';
import 'package:threemojo_app/features/session/domain/entities/online_session.dart';
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
import 'package:threemojo_app/features/session/presentation/pages/ui_home.dart';
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

import '../../support/build_providers.dart';
import '../../support/fake_paywall.dart';
import '../../support/fake_repositories.dart';
import '../../support/fake_safety.dart';

// ---------------------------------------------------------------------------
// Il mondo **reale** del test: ogni repository è un finto che ricorda cosa
// gli è stato chiesto. La demo non deve toccarne nessuno.
// ---------------------------------------------------------------------------

class _FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<Either<Failure, bool>> getFakeMode() async => const Right(false);

  @override
  Future<Either<Failure, Unit>> setFakeMode(bool enabled) async =>
      const Right(unit);

  @override
  Future<Either<Failure, AppLanguage>> getLanguage() async =>
      const Right(AppLanguage.english);

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

/// La fotocamera vera: non deve mai scattare durante la demo.
class _SpySelfieRepository implements SelfieRepository {
  int calls = 0;

  @override
  Future<Either<Failure, Uint8List?>> takeSelfie() async {
    calls++;
    return Right(
      Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
    );
  }

  @override
  Future<Either<Failure, Uint8List>> flipHorizontally(
    Uint8List selfieBytes,
  ) async {
    calls++;
    return Right(selfieBytes);
  }

  @override
  Future<Either<Failure, Unit>> discardLeftoverFiles() async {
    calls++;
    return const Right(unit);
  }
}

/// Il GPS vero: nessuna chiamata (permesso, posizione) durante la demo.
class _SpyLocationRepository implements LocationRepository {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    return super.noSuchMethod(invocation);
  }
}

/// "Vicinanze" vera (connessione al server): mai aperta durante la demo.
class _SpyWatchNearbyPeopleUseCase implements WatchNearbyPeopleUseCase {
  int calls = 0;

  @override
  Stream<Either<Failure, List<NearbyPerson>>> call({
    required BackgroundLocationNotice backgroundNotice,
  }) {
    calls++;
    return const Stream.empty();
  }
}

/// Il negozio vero: la demo non deve mai aprirlo.
class _SpyStore implements StoreBillingDataSource {
  int buyCalls = 0;
  int completeCalls = 0;

  @override
  Future<UnlockOffer> loadUnlockOffer() async =>
      const UnlockOffer.store('1,09 €');

  @override
  Future<StoreCheckout> buyUnlock() async {
    buyCalls++;
    throw StateError('the real store must never be used by the demo');
  }

  @override
  Stream<StorePurchase> get unfinishedPurchases => const Stream.empty();

  @override
  List<StorePurchase> get knownUnfinishedPurchases => const [];

  @override
  Future<void> completePurchase(StorePurchase purchase) async =>
      completeCalls++;
}

class _RealWorld {
  final sessions = FakeSessionRepository();
  final profiles = FakeProfileRepository(saved: testProfile);
  final selfies = _SpySelfieRepository();
  final faces = FakeFaceDetectionRepository();
  final connection = FakeConnectionRepository();
  final location = _SpyLocationRepository();
  final nearby = _SpyWatchNearbyPeopleUseCase();
  final paywall = FakePaywallServer();
  final store = _SpyStore();
  final encounters = FakeEncounterRepository();
  final chat = FakeChatRepository();
  final safety = buildSafety();

  /// Nessun repository reale è stato usato (oltre ai normali ascolti del
  /// ciclo di vita, che da offline non fanno partire nulla).
  void expectUntouched() {
    expect(sessions.current, isNull, reason: 'real session must stay off');
    expect(selfies.calls, 0, reason: 'real camera used');
    expect(faces.checked, isEmpty, reason: 'real face check used');
    expect(location.calls, 0, reason: 'real GPS used');
    expect(nearby.calls, 0, reason: 'real Nearby connection opened');
    expect(connection.checkCalls, 0, reason: 'real connection checked');
    expect(paywall.statusCalls, 0, reason: 'real paywall server asked');
    expect(paywall.redeemCalls, 0, reason: 'real paywall server asked');
    expect(store.buyCalls, 0, reason: 'real store opened');
    expect(store.completeCalls, 0, reason: 'real store used');
    expect(encounters.watchCalls, 0, reason: 'real requests listened to');
    expect(encounters.sentTo, isEmpty, reason: 'real request sent');
    expect(encounters.responses, isEmpty, reason: 'real answer sent');
    expect(encounters.endedMatches, isEmpty, reason: 'real match ended');
    expect(chat.opened, isEmpty, reason: 'real chat opened');
    expect(chat.startedReceiving, isEmpty, reason: 'real chat listened to');
    expect(safety.remote.blocked, isEmpty, reason: 'real block sent');
    expect(safety.remote.reported, isEmpty, reason: 'real report sent');
    expect(
      RealtimeConnection.instance.status,
      RealtimeStatus.offline,
      reason: 'the WebSocket must never be opened by the demo',
    );
  }

  Widget build() {
    final endSession = EndSessionUseCase(repository: sessions);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ProSettings(
            getLanguageUseCase: GetLanguageUseCase(_FakeSettingsRepository()),
            setLanguageUseCase: SetLanguageUseCase(_FakeSettingsRepository()),
            getThemeModeUseCase: GetThemeModeUseCase(_FakeSettingsRepository()),
            setThemeModeUseCase: SetThemeModeUseCase(_FakeSettingsRepository()),
            getFakeModeUseCase: GetFakeModeUseCase(
              _FakeSettingsRepository(),
              isAvailable: false,
            ),
            setFakeModeUseCase: SetFakeModeUseCase(
              _FakeSettingsRepository(),
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
            watchNearbyPeopleUseCase: nearby,
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
          create: (_) => buildProPaywall(
            sessions: sessions,
            paywall: paywall,
            store: store,
          ),
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

/// Fa scorrere il tempo a piccoli passi (timer, microtask, frame): senza
/// `pumpAndSettle`, che con gli indicatori animati non finirebbe mai.
Future<void> _advance(WidgetTester tester, Duration duration) async {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    await tester.pump(step);
    elapsed += step;
  }
}

T _demo<T>(WidgetTester tester) =>
    Provider.of<T>(tester.element(find.byType(UiHome)), listen: false);

void main() {
  wakelockPlusPlatformInstance = _FakeWakelockPlusPlatform();

  late _RealWorld world;
  late AppLocalizations l10n;

  setUp(() async {
    world = _RealWorld();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(world.build());
    await _advance(tester, const Duration(milliseconds: 300));
  }

  Future<void> enterFromHomeLink(WidgetTester tester) async {
    await tester.tap(find.text(l10n.demo_try_link));
    await _advance(tester, const Duration(milliseconds: 500));
  }

  Future<void> exitFromBanner(WidgetTester tester) async {
    await tester.tap(find.text(l10n.demo_exit));
    await _advance(tester, const Duration(seconds: 1));
  }

  testWidgets('the offline home offers the demo; entering it opens no real '
      'connection and shows only declared demo people', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    expect(find.text(l10n.start), findsOneWidget);
    expect(find.text(l10n.demo_try_link), findsOneWidget);
    expect(find.text(l10n.demo_banner_title), findsNothing);

    await enterFromHomeLink(tester);

    // Banner fisso, Vicinanze popolata subito con la riga sull'attesa vera.
    expect(find.text(l10n.demo_banner_title), findsOneWidget);
    expect(find.text(l10n.demo_exit), findsOneWidget);
    expect(find.text(l10n.demo_nearby_note), findsOneWidget);
    expect(find.text(l10n.start), findsNothing);
    final tiles = find.byType(CmpNearbyPersonTile);
    expect(tiles, findsNWidgets(5));
    // Ogni persona ha il badge "Demo", letto come "Persona dimostrativa".
    expect(
      find.descendant(of: tiles, matching: find.byType(CmpDemoBadge)),
      findsNWidgets(5),
    );
    // (Ogni tile è un solo nodo per lo screen reader: la frase è dentro la
    // sua etichetta.)
    expect(
      find.bySemanticsLabel(RegExp(l10n.demo_person_semantics)),
      findsNWidgets(5),
    );
    // I tre stadi della probabilità d'incontro.
    expect(find.text(l10n.low_chance_to_meet), findsWidgets);
    expect(find.text(l10n.medium_chance_to_meet), findsWidgets);
    expect(find.text(l10n.high_chance_to_meet), findsWidgets);
    // Nessun drawer nella demo (profilo e impostazioni sono del mondo vero).
    expect(find.byTooltip('Open navigation menu'), findsNothing);

    world.expectUntouched();

    await exitFromBanner(tester);
    semantics.dispose();
  });

  testWidgets('request → simulated yes → match → chat with automatic '
      'replies; Block acts only locally', (tester) async {
    await pumpApp(tester);
    await enterFromHomeLink(tester);

    // Una persona libera dal paywall.
    final free = find.byWidgetPredicate(
      (widget) => widget is CmpNearbyPersonTile && !widget.isLocked,
    );
    expect(free, findsNWidgets(2));
    await tester.tap(free.first);
    await _advance(tester, const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('proposal-chat')));
    await _advance(tester, const Duration(milliseconds: 600));
    expect(find.text(l10n.request_sent), findsWidgets);

    // Il "sì" simulato arriva dopo 3 s: si apre la pagina del match.
    await _advance(tester, const Duration(seconds: 4));
    final match = find.byType(UiActiveMatch);
    expect(match, findsOneWidget);
    expect(
      find.descendant(of: match, matching: find.byType(CmpDemoBadge)),
      findsOneWidget,
    );
    expect(find.text(l10n.demo_banner_title), findsOneWidget);

    // Gli avvisi della richiesta coprirebbero il bottone di invio.
    ScaffoldMessenger.of(tester.element(match)).clearSnackBars();
    await _advance(tester, const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'Ciao!');
    await tester.tap(find.byIcon(Icons.send));
    await _advance(tester, const Duration(seconds: 4));
    // (Il testo del messaggio è un `Text.rich`, con l'ora dentro.)
    expect(find.textContaining('Ciao!', findRichText: true), findsOneWidget);
    expect(
      find.textContaining(l10n.demo_chat_reply_1, findRichText: true),
      findsOneWidget,
    );

    // Blocca: il dialogo dice che in demo non parte nulla.
    await tester.tap(
      find.descendant(of: match, matching: find.byIcon(Icons.more_vert)),
    );
    await _advance(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text(l10n.block).last);
    await _advance(tester, const Duration(milliseconds: 500));
    expect(find.text(l10n.demo_nothing_is_sent), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l10n.block));
    await _advance(tester, const Duration(seconds: 1));

    // La persona bloccata sparisce, il match si chiude: solo nella demo.
    expect(find.byType(UiActiveMatch), findsNothing);
    expect(find.byType(CmpNearbyPersonTile), findsNWidgets(4));
    world.expectUntouched();

    await exitFromBanner(tester);
  });

  testWidgets('an incoming demo request arrives from a person in the list, '
      'with its badge; saying yes opens the match', (tester) async {
    await pumpApp(tester);
    await enterFromHomeLink(tester);

    await _advance(tester, const Duration(seconds: 16));
    expect(find.text(l10n.wants_to_meet_you), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.requests));
    await _advance(tester, const Duration(milliseconds: 600));
    final request = find.byType(CmpIncomingRequestTile);
    expect(request, findsOneWidget);
    expect(
      find.descendant(of: request, matching: find.byType(CmpDemoBadge)),
      findsOneWidget,
    );

    await tester.tap(find.text(l10n.yes));
    await _advance(tester, const Duration(seconds: 1));
    expect(find.byType(UiActiveMatch), findsOneWidget);
    world.expectUntouched();

    await exitFromBanner(tester);
    expect(find.byType(UiActiveMatch), findsNothing);
    expect(find.text(l10n.start), findsOneWidget);
  });

  testWidgets('the demo unlock is free and simulated ("Demo: no payment"), '
      'with the timer chip; the real store is never used', (tester) async {
    await pumpApp(tester);
    await enterFromHomeLink(tester);

    await tester.tap(find.text(l10n.demo_unlock_button));
    await _advance(tester, const Duration(milliseconds: 500));
    expect(find.text(l10n.demo_unlock_dialog_body), findsOneWidget);
    await tester.tap(find.text(l10n.demo_unlock_confirm));
    await _advance(tester, const Duration(seconds: 2));

    expect(_demo<ProPaywall>(tester).isUnlocked, isTrue);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CmpNearbyPersonTile && widget.isLocked,
      ),
      findsNothing,
    );
    expect(find.text(l10n.demo_unlock_button), findsNothing);
    world.expectUntouched();

    // Uscendo lo sblocco della demo sparisce: il paywall vero non sa nulla.
    await exitFromBanner(tester);
    final realPaywall = Provider.of<ProPaywall>(
      tester.element(find.byType(UiHome)),
      listen: false,
    );
    expect(realPaywall.isUnlocked, isFalse);
    world.expectUntouched();
  });

  testWidgets('exiting the demo (banner or End) wipes it and goes back to '
      'the real offline home; entering again starts from scratch', (
    tester,
  ) async {
    await pumpApp(tester);
    await enterFromHomeLink(tester);

    // Una richiesta, poi fuori dal banner.
    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) => widget is CmpNearbyPersonTile && !widget.isLocked,
          )
          .first,
    );
    await _advance(tester, const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('proposal-sayHi')));
    await _advance(tester, const Duration(milliseconds: 300));
    expect(find.text(l10n.request_sent), findsWidgets);

    await exitFromBanner(tester);
    expect(find.text(l10n.demo_banner_title), findsNothing);
    expect(find.text(l10n.start), findsOneWidget);
    expect(find.byType(CmpDemoBadge), findsNothing);
    expect(
      Provider.of<ProSession>(
        tester.element(find.byType(UiHome)),
        listen: false,
      ).isOnline,
      isFalse,
    );
    world.expectUntouched();

    // Di nuovo dentro: nessuna traccia della richiesta di prima.
    await enterFromHomeLink(tester);
    expect(find.byType(CmpNearbyPersonTile), findsNWidgets(5));
    expect(find.text(l10n.request_sent), findsNothing);

    // End nell'AppBar della demo fa uscire dalla demo, come il banner.
    await tester.tap(find.text(l10n.end_session));
    await _advance(tester, const Duration(seconds: 1));
    expect(find.text(l10n.demo_banner_title), findsNothing);
    expect(find.text(l10n.start), findsOneWidget);
    world.expectUntouched();
  });

  testWidgets('the drawer offers the demo only while offline', (tester) async {
    await pumpApp(tester);

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffold.openDrawer();
    await _advance(tester, const Duration(milliseconds: 500));
    expect(find.text(l10n.demo_drawer_item), findsOneWidget);
    await tester.tap(find.text(l10n.demo_drawer_item));
    await _advance(tester, const Duration(milliseconds: 600));
    expect(find.text(l10n.demo_banner_title), findsOneWidget);
    await exitFromBanner(tester);

    // Sessione reale: niente demo, né dal drawer né da `ProDemo`.
    world.sessions.start(
      OnlineSession(
        sessionId: 'real',
        selfieBytes: illustratedAvatarPng(9),
        profile: testProfile,
      ),
    );
    await _advance(tester, const Duration(milliseconds: 300));
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await _advance(tester, const Duration(milliseconds: 500));
    expect(find.text(l10n.my_profile), findsOneWidget);
    expect(find.text(l10n.demo_drawer_item), findsNothing);

    final proDemo = Provider.of<ProDemo>(
      tester.element(find.byType(UiHome)),
      listen: false,
    );
    expect(await proDemo.enter(), isA<DemoUnavailableDuringSessionFailure>());
    expect(proDemo.isActive, isFalse);
    world.sessions.end();
    await _advance(tester, const Duration(milliseconds: 300));
  });

  testWidgets('the demo can be tried before filling in the profile', (
    tester,
  ) async {
    world.profiles.saved = null;
    await pumpApp(tester);
    expect(find.text(l10n.demo_try_link), findsOneWidget);

    await tester.tap(find.text(l10n.demo_try_link));
    await _advance(tester, const Duration(milliseconds: 500));
    expect(find.byType(CmpNearbyPersonTile), findsNWidgets(5));
    expect(world.profiles.saved, isNull);

    await exitFromBanner(tester);
    expect(find.text(l10n.demo_try_link), findsOneWidget);
    world.expectUntouched();
  });

  group('domain', () {
    test('the demo can be entered only while offline', () async {
      final sessions = FakeSessionRepository();
      final check = CheckDemoAvailableUseCase(
        GetCurrentSessionUseCase(sessions),
      );
      expect((await check(const NoParams())).isRight(), isTrue);

      sessions.start(testSession('real'));
      expect(
        (await check(const NoParams())).getLeft().toNullable(),
        isA<DemoUnavailableDuringSessionFailure>(),
      );
    });

    test('the demo session has an illustrated selfie and a neutral profile '
        '(no sensitive data, no consent needed)', () async {
      final sessions = FakeSessionRepository();
      final start = StartDemoSessionUseCase(
        repository: sessions,
        takeSelfieUseCase: TakeSelfieUseCase(
          SelfieRepositoryImpl(SelfieLocalDataSourceFakeImpl()),
        ),
      );

      final session = (await start(
        const NoParams(),
      )).getOrElse((failure) => throw failure);

      expect(session.sessionId, startsWith('demo-'));
      expect(session.profile.gender, Gender.unspecified);
      expect(session.profile.looksForEveryone, isTrue);
      expect(session.profile.needsSensitiveDataConsent, isFalse);
      expect(
        session.selfieBytes,
        same(illustratedAvatarPng(SelfieLocalDataSourceFakeImpl.ownAvatarSeed)),
      );
    });

    test('illustrated avatars are real PNGs, generated locally, the same '
        'bytes for the same seed', () {
      final avatar = illustratedAvatarPng(3);
      expect(avatar.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(img.decodePng(avatar)?.width, 160);
      expect(identical(illustratedAvatarPng(3), avatar), isTrue);
      expect(illustratedAvatarPng(4), isNot(equals(avatar)));
    });

    test('the demo store offers a free demo unlock and pays for real '
        'nothing', () async {
      final store = StoreBillingDataSourceFakeImpl.demo(
        sheetDelay: Duration.zero,
      );
      expect(await store.loadUnlockOffer(), const UnlockOffer.demo());
      expect(await store.buyUnlock(), isA<StoreCheckoutPurchased>());
    });
  });
}
