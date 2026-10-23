import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:provider/provider.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/theme/app_theme.dart';
import 'package:threemojo_app/features/paywall/domain/entities/store_purchase.dart';
import 'package:threemojo_app/features/paywall/domain/repositories/paywall_repository.dart';
import 'package:threemojo_app/features/paywall/presentation/providers/pro_paywall.dart';
import 'package:threemojo_app/features/paywall/presentation/widgets/cmp_unlock_chip.dart';
import 'package:threemojo_app/features/paywall/presentation/widgets/cmp_unlock_expired_listener.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import '../../support/fake_paywall.dart';
import '../../support/fake_repositories.dart';

/// Server finto con la scadenza sul suo orologio ([now]).
class _ServerPaywall implements PaywallRepository {
  _ServerPaywall(this.now, this.expiresAt);

  final DateTime Function() now;
  final DateTime expiresAt;

  @override
  Future<Either<Failure, Duration>> getUnlockTimeRemaining() async {
    final remaining = expiresAt.difference(now());
    return Right(remaining > Duration.zero ? remaining : Duration.zero);
  }

  @override
  Future<Either<Failure, Duration>> redeemPurchase(
    StorePurchase purchase,
  ) async => const Left(UnexpectedFailure('not used'));
}

void main() {
  // 21:33:00 + 1 h 42 min 30 s = 23:15:30.
  final start = DateTime(2026, 10, 22, 21, 33);
  late DateTime clock;
  late ProPaywall proPaywall;

  /// Dentro il test (non in `setUp`): i timer di `ProPaywall` devono nascere
  /// nella zona a tempo finto di `testWidgets`.
  void buildProvider() {
    clock = start;
    DateTime now() => clock;
    final repo = _ServerPaywall(
      now,
      start.add(const Duration(hours: 1, minutes: 42, seconds: 30)),
    );
    proPaywall = buildProPaywall(
      sessions: FakeSessionRepository(current: testSession('s1')),
      paywall: repo,
      now: now,
    );
  }

  /// Fa passare [duration] sia sull'orologio iniettato sia sui timer finti.
  Future<void> advance(WidgetTester tester, Duration duration) async {
    clock = clock.add(duration);
    await tester.pump(duration);
    await tester.pump();
  }

  Future<AppLocalizations> pumpChip(
    WidgetTester tester, {
    Locale locale = const Locale('it'),
  }) async {
    buildProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: proPaywall,
        child: MaterialApp(
          theme: AppTheme.light,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CmpUnlockExpiredListener(
            child: Scaffold(body: Column(children: [CmpUnlockChip()])),
          ),
        ),
      ),
    );
    await tester.pump();
    return AppLocalizations.delegate.load(locale);
  }

  testWidgets('shows the time left in hours and minutes, updated on the '
      'minute', (tester) async {
    await pumpChip(tester);

    expect(find.text('Sbloccato · ancora 1 h 42 min'), findsOneWidget);

    await advance(tester, const Duration(seconds: 29));
    expect(find.text('Sbloccato · ancora 1 h 42 min'), findsOneWidget);

    await advance(tester, const Duration(seconds: 1));
    expect(find.text('Sbloccato · ancora 1 h 41 min'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });

  testWidgets('screen readers get the time in words, as a live region and a '
      'button', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpChip(tester);

    expect(
      tester.getSemantics(find.byType(ActionChip)),
      matchesSemantics(
        label: 'Sbloccato, ancora 1 ora e 42 minuti',
        isLiveRegion: true,
        isButton: true,
        hasTapAction: true,
      ),
    );

    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });

  testWidgets('a tap shows until when, in the language format, and that time '
      'keeps running', (tester) async {
    final l10n = await pumpChip(tester);

    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    expect(find.text('Sbloccato fino alle 23:15'), findsOneWidget);
    expect(find.text(l10n.unlock_details_time_runs), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });

  testWidgets('English: "left" and a 12-hour expiry time', (tester) async {
    await pumpChip(tester, locale: const Locale('en'));

    expect(find.text('Unlocked · 1 h 42 min left'), findsOneWidget);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    expect(find.text('Unlocked until 11:15 PM'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });

  testWidgets('the last 10 minutes only change the colours; at the expiry the '
      'chip goes away and "Unlock expired" shows once', (tester) async {
    final l10n = await pumpChip(tester);
    final colorScheme = AppTheme.light.colorScheme;
    Color? chipColor() =>
        tester.widget<ActionChip>(find.byType(ActionChip)).backgroundColor;

    expect(chipColor(), colorScheme.primaryContainer);

    // Fino a 10 min 30 s dalla fine: ancora i colori normali.
    await advance(tester, const Duration(hours: 1, minutes: 32));
    expect(find.text('Sbloccato · ancora 10 min'), findsOneWidget);
    expect(chipColor(), colorScheme.primaryContainer);

    await advance(tester, const Duration(seconds: 30));
    expect(find.text('Sbloccato · ancora 9 min'), findsOneWidget);
    expect(chipColor(), colorScheme.secondaryContainer);

    await advance(tester, const Duration(minutes: 9, seconds: 1));
    expect(find.text('Sbloccato · ancora meno di un minuto'), findsOneWidget);

    await advance(tester, const Duration(minutes: 1));
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text(l10n.unlock_expired), findsOneWidget);

    // La snackbar se ne va da sola; nessun altro avviso, nemmeno ai
    // controlli successivi dello stato.
    await advance(tester, const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await advance(tester, const Duration(minutes: 30));
    await tester.pumpAndSettle();
    expect(find.text(l10n.unlock_expired), findsNothing);
    expect(find.byType(ActionChip), findsNothing);

    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });
}
