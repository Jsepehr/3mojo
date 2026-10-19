import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:provider/provider.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/usecases/usecase.dart';
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
import 'package:threemojo_app/features/settings/presentation/widgets/cmp_app_drawer.dart';
import 'package:threemojo_app/features/settings/presentation/widgets/cmp_language_picker_dialog.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

/// Impostazioni in memoria. [fakeMode] parte `true`: come un valore
/// salvato da una versione (o un build di debug) precedente.
class _FakeSettingsRepository implements SettingsRepository {
  bool fakeMode = true;
  int setFakeModeCalls = 0;

  @override
  Future<Either<Failure, bool>> getFakeMode() async => Right(fakeMode);

  @override
  Future<Either<Failure, Unit>> setFakeMode(bool enabled) async {
    setFakeModeCalls++;
    fakeMode = enabled;
    return const Right(unit);
  }

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

ProSettings _proSettings(
  SettingsRepository repository, {
  required bool available,
}) => ProSettings(
  getLanguageUseCase: GetLanguageUseCase(repository),
  setLanguageUseCase: SetLanguageUseCase(repository),
  getThemeModeUseCase: GetThemeModeUseCase(repository),
  setThemeModeUseCase: SetThemeModeUseCase(repository),
  getFakeModeUseCase: GetFakeModeUseCase(repository, isAvailable: available),
  setFakeModeUseCase: SetFakeModeUseCase(repository, isAvailable: available),
);

void main() {
  late _FakeSettingsRepository repository;

  setUp(() => repository = _FakeSettingsRepository());

  group('fake mode where it is not available (release builds)', () {
    test('is off even if an old saved value says "fake"', () async {
      final result = await GetFakeModeUseCase(repository, isAvailable: false)(
        const NoParams(),
      );

      expect(result.getRight().toNullable(), isFalse);
    });

    test('cannot be switched on; switching it off is allowed', () async {
      final setFakeMode = SetFakeModeUseCase(repository, isAvailable: false);

      expect((await setFakeMode(true)).isLeft(), isTrue);
      expect(repository.setFakeModeCalls, 0);

      expect((await setFakeMode(false)).isRight(), isTrue);
      expect(repository.fakeMode, isFalse);
    });

    test('where available (debug builds) the saved value is used', () async {
      final result = await GetFakeModeUseCase(repository, isAvailable: true)(
        const NoParams(),
      );

      expect(result.getRight().toNullable(), isTrue);
    });
  });

  group('CmpAppDrawer', () {
    Future<AppLocalizations> pumpDrawer(
      WidgetTester tester,
      ProSettings proSettings,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: proSettings,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(drawer: CmpAppDrawer(), body: SizedBox()),
          ),
        ),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pumpAndSettle();
      return l10n;
    }

    testWidgets('has a header with the app name, and no fake-data switch '
        'where fake mode is not available', (tester) async {
      final l10n = await pumpDrawer(
        tester,
        _proSettings(repository, available: false),
      );

      expect(find.text(l10n.app_title), findsOneWidget);
      expect(find.text(l10n.fake_data_no_network), findsNothing);
      expect(find.text(l10n.developer_options), findsNothing);
    });

    testWidgets('shows the fake-data switch, at the bottom, where available', (
      tester,
    ) async {
      final l10n = await pumpDrawer(
        tester,
        _proSettings(repository, available: true),
      );

      expect(find.text(l10n.developer_options), findsOneWidget);
      final fakeSwitch = find.text(l10n.fake_data_no_network);
      expect(fakeSwitch, findsOneWidget);
      expect(
        tester.getTopLeft(fakeSwitch).dy,
        greaterThan(tester.getTopLeft(find.text(l10n.share_app)).dy),
      );
    });

    testWidgets('"Change language" closes the drawer and still opens the '
        'dialog (no use of the unmounted drawer context)', (tester) async {
      final l10n = await pumpDrawer(
        tester,
        _proSettings(repository, available: false),
      );

      await tester.tap(find.text(l10n.change_language));
      await tester.pumpAndSettle();

      expect(find.byType(CmpAppDrawer), findsNothing);
      expect(find.byType(CmpLanguagePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
