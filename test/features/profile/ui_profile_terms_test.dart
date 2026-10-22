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
import 'package:threemojo_app/features/safety/presentation/pages/ui_terms_of_use.dart';
import 'package:threemojo_app/features/session/domain/repositories/selfie_repository.dart';
import 'package:threemojo_app/features/session/domain/usecases/check_selfie_has_face_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/end_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/flip_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/start_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/take_selfie_usecase.dart';
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

void main() {
  wakelockPlusPlatformInstance = _FakeWakelockPlusPlatform();

  late FakeProfileRepository profiles;
  late ProSession proSession;
  late ProProfile proProfile;
  late AppLocalizations l10n;

  setUp(() async {
    final sessions = FakeSessionRepository();
    profiles = FakeProfileRepository();
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

  testWidgets('onboarding: the profile cannot be saved until the terms of '
      'use are accepted, and the acceptance is saved with it', (tester) async {
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
          home: const UiProfile(isOnboarding: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text(l10n.prefer_not_to_say));
    await tapVisible(tester, find.text(l10n.everyone));
    await tapVisible(
      tester,
      find.text(l10n.i_confirm_i_am_at_least_18_years_old),
    );

    final save = find.widgetWithText(FilledButton, l10n.save);
    await tester.ensureVisible(save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    // "Leggi i termini" apre la pagina, e si torna indietro.
    await tapVisible(tester, find.text(l10n.read_the_terms));
    expect(find.byType(UiTermsOfUse), findsOneWidget);
    expect(find.text(l10n.terms_rule_enforcement), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text(l10n.terms_accept_checkbox));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tapVisible(tester, save);

    expect(profiles.saved?.acceptedTermsVersion, Profile.currentTermsVersion);
  });
}
