import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/profile/domain/usecases/delete_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/get_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/save_profile_usecase.dart';
import 'package:threemojo_app/features/profile/presentation/providers/pro_profile.dart';
import 'package:threemojo_app/features/session/domain/repositories/selfie_repository.dart';
import 'package:threemojo_app/features/session/domain/usecases/check_selfie_has_face_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/end_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/flip_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/start_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/take_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/withdraw_profile_usecase.dart';
import 'package:threemojo_app/features/session/presentation/pages/ui_start_session.dart';
import 'package:threemojo_app/features/session/presentation/providers/pro_session.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import '../../support/fake_repositories.dart';

/// Fotocamera finta: ogni scatto è una piccola immagine vera (così
/// `Image` la può disegnare) e diversa dalla precedente.
class _FakeSelfieRepository implements SelfieRepository {
  int shots = 0;

  @override
  Future<Either<Failure, Uint8List?>> takeSelfie() async {
    shots++;
    return Right(
      Uint8List.fromList(img.encodePng(img.Image(width: 2, height: shots))),
    );
  }

  @override
  Future<Either<Failure, Uint8List>> flipHorizontally(
    Uint8List selfieBytes,
  ) async => Right(selfieBytes);

  @override
  Future<Either<Failure, Unit>> discardLeftoverFiles() async =>
      const Right(unit);
}

class _FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

void main() {
  wakelockPlusPlatformInstance = _FakeWakelockPlusPlatform();

  late FakeSessionRepository sessions;
  late FakeFaceDetectionRepository faces;
  late FakeProfileRepository profiles;
  late ProSession proSession;
  late ProProfile proProfile;
  late AppLocalizations l10n;

  setUp(() async {
    sessions = FakeSessionRepository();
    faces = FakeFaceDetectionRepository(result: const Right(false));
    profiles = FakeProfileRepository(saved: testProfile);
    final selfies = _FakeSelfieRepository();
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

  Future<void> pumpHost(WidgetTester tester) async {
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
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const UiStartSession())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openWizard(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> shootAndConfirm(WidgetTester tester) async {
    await tester.tap(find.text(l10n.take_a_selfie));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.i_like_it_continue));
    await tester.pumpAndSettle();
  }

  testWidgets('a selfie without a face shows the translated text for that '
      'error, and a new shot clears it', (tester) async {
    await pumpHost(tester);
    await openWizard(tester);

    await shootAndConfirm(tester);
    expect(find.text(l10n.selfie_error_no_face), findsOneWidget);

    await tester.tap(find.text(l10n.retake));
    await tester.pumpAndSettle();
    expect(find.text(l10n.selfie_error_no_face), findsNothing);
  });

  testWidgets('reopening the wizard does not show the error of the previous '
      'attempt', (tester) async {
    await pumpHost(tester);
    await openWizard(tester);
    await shootAndConfirm(tester);
    expect(proSession.failure, isA<NoFaceInSelfieFailure>());

    await tester.pageBack();
    await tester.pumpAndSettle();
    await openWizard(tester);

    expect(proSession.failure, isNull);
    expect(find.text(l10n.selfie_error_no_face), findsNothing);
  });

  testWidgets('with a face, the wizard goes online and closes', (tester) async {
    faces.result = const Right(true);
    await pumpHost(tester);
    await openWizard(tester);

    await shootAndConfirm(tester);
    await tester.tap(find.widgetWithText(FilledButton, l10n.go_online_button));
    await tester.pumpAndSettle();

    expect(proSession.isOnline, isTrue);
    expect(find.byType(UiStartSession), findsNothing);
    // Lo stesso selfie scattato è quello controllato e messo in sessione.
    expect(faces.checked.last, sessions.current!.selfieBytes);
  });

  testWidgets('a profile saved before the terms of use existed is asked to '
      'accept them at Start, and then goes online', (tester) async {
    faces.result = const Right(true);
    profiles.saved = const Profile(
      gender: Gender.male,
      lookingFor: Profile.searchableGenders,
      isAdultConfirmed: true,
      sensitiveDataConsent: true,
    );
    await pumpHost(tester);
    await openWizard(tester);
    await shootAndConfirm(tester);

    await tester.tap(find.widgetWithText(FilledButton, l10n.go_online_button));
    await tester.pumpAndSettle();

    expect(proSession.isOnline, isFalse);
    expect(find.text(l10n.terms_accept_dialog_body), findsOneWidget);
    final accept = find.widgetWithText(FilledButton, l10n.accept);
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);

    await tester.ensureVisible(find.text(l10n.terms_accept_checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.terms_accept_checkbox));
    await tester.pump();
    await tester.tap(accept);
    await tester.pumpAndSettle();

    expect(profiles.saved?.hasAcceptedCurrentTerms, isTrue);
    expect(proSession.isOnline, isTrue);
    expect(find.byType(UiStartSession), findsNothing);
  });

  testWidgets('declining the terms keeps you offline, with the reason on '
      'screen', (tester) async {
    faces.result = const Right(true);
    profiles.saved = const Profile(
      gender: Gender.male,
      lookingFor: Profile.searchableGenders,
      isAdultConfirmed: true,
      sensitiveDataConsent: true,
    );
    await pumpHost(tester);
    await openWizard(tester);
    await shootAndConfirm(tester);
    await tester.tap(find.widgetWithText(FilledButton, l10n.go_online_button));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    expect(proSession.isOnline, isFalse);
    expect(profiles.saved?.hasAcceptedCurrentTerms, isFalse);
    expect(find.text(l10n.start_error_terms_required), findsOneWidget);
  });
}
