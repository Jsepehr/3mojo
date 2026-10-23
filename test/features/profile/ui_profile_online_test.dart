import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/profile/domain/usecases/delete_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/get_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/save_profile_usecase.dart';
import 'package:threemojo_app/features/profile/presentation/pages/ui_profile.dart';
import 'package:threemojo_app/features/profile/presentation/providers/pro_profile.dart';
import 'package:threemojo_app/features/session/domain/repositories/selfie_repository.dart';
import 'package:threemojo_app/features/session/domain/usecases/check_selfie_has_face_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/end_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/flip_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/start_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/take_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/update_profile_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/withdraw_profile_usecase.dart';
import 'package:threemojo_app/features/session/presentation/providers/pro_session.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import '../../support/fake_repositories.dart';

class _FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

class _UnusedSelfieRepository implements SelfieRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not needed for this test');
}

/// Il profilo modificato **da online**: le modifiche al dato sensibile
/// chiedono conferma e chiudono prima la sessione; le altre no.
void main() {
  wakelockPlusPlatformInstance = _FakeWakelockPlusPlatform();

  late FakeSessionRepository sessions;
  late FakeProfileRepository profiles;
  late ProSession proSession;
  late ProProfile proProfile;
  late AppLocalizations l10n;

  setUp(() async {
    sessions = FakeSessionRepository(current: testSession('s1'));
    profiles = FakeProfileRepository(saved: testProfile);
    final faces = FakeFaceDetectionRepository();
    final selfies = _UnusedSelfieRepository();
    final endSession = EndSessionUseCase(repository: sessions);
    proSession = ProSession(
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
    );
    proProfile = ProProfile(
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
    );
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() {
    proSession.dispose();
    proProfile.dispose();
  });

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// La pagina profilo aperta dal menu, sopra una home finta.
  Future<void> openProfile(WidgetTester tester) async {
    // Alta abbastanza da costruire tutta la pagina, fino al bottone Salva.
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: proSession),
          ChangeNotifierProvider.value(value: proProfile),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const UiProfile())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(proSession.isOnline, isTrue);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('online, the page says what applies when', (tester) async {
    await openProfile(tester);

    expect(find.text(l10n.profile_online_changes_hint), findsOneWidget);
  });

  testWidgets('changing the gender from online: confirmation, then the '
      'session ends before the profile is saved', (tester) async {
    await openProfile(tester);

    await tapVisible(tester, find.text(l10n.female));
    await tapVisible(tester, find.widgetWithText(FilledButton, l10n.save));

    expect(find.text(l10n.profile_save_ends_session_body), findsOneWidget);
    await tester.tap(find.text(l10n.profile_save_and_end));
    await tester.pumpAndSettle();
    // ProSession (creata fuori dalla zona del test) segue lo stream della
    // sessione: si lascia arrivare l'evento di fine sessione.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(sessions.endSessionCalls, 1);
    expect(proSession.isOnline, isFalse);
    expect(profiles.saved!.gender, Gender.female);
    expect(find.byType(UiProfile), findsNothing);
    expect(find.text(l10n.profile_saved_session_ended), findsOneWidget);
  });

  testWidgets('cancelling the confirmation keeps you online and saves '
      'nothing', (tester) async {
    await openProfile(tester);

    await tapVisible(tester, find.text(l10n.female));
    await tapVisible(tester, find.widgetWithText(FilledButton, l10n.save));
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    expect(sessions.endSessionCalls, 0);
    expect(proSession.isOnline, isTrue);
    expect(profiles.saved, testProfile);
    expect(find.byType(UiProfile), findsOneWidget);
  });

  testWidgets('changing only the languages from online: no confirmation, '
      'saved, still online', (tester) async {
    await openProfile(tester);

    await tapVisible(tester, find.text('IT'));
    await tapVisible(tester, find.widgetWithText(FilledButton, l10n.save));

    expect(find.text(l10n.profile_save_ends_session_body), findsNothing);
    expect(sessions.endSessionCalls, 0);
    expect(proSession.isOnline, isTrue);
    expect(profiles.saved!.languages, ['it']);
    expect(find.text(l10n.profile_saved), findsOneWidget);
  });
}
