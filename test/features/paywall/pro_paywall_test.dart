import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:provider/provider.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/paywall/domain/repositories/paywall_repository.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/get_unlock_status_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/purchase_unlock_usecase.dart';
import 'package:threemojo_app/features/paywall/presentation/providers/pro_paywall.dart';
import 'package:threemojo_app/features/paywall/presentation/widgets/cmp_paywall_banner.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import '../../support/fake_repositories.dart';

class _FakePaywallRepository implements PaywallRepository {
  Either<Failure, Unit> purchaseResult = const Right(unit);
  int statusCalls = 0;
  int purchaseCalls = 0;

  @override
  Future<Either<Failure, bool>> isUnlocked() async {
    statusCalls++;
    return const Right(false);
  }

  @override
  Future<Either<Failure, Unit>> purchaseUnlock() async {
    purchaseCalls++;
    return purchaseResult;
  }
}

ProPaywall _build(FakeSessionRepository sessions, PaywallRepository repo) =>
    ProPaywall(
      watchSessionUseCase: WatchSessionUseCase(sessions),
      getUnlockStatusUseCase: GetUnlockStatusUseCase(repo),
      purchaseUnlockUseCase: PurchaseUnlockUseCase(repo),
    );

void main() {
  test('a failed purchase returns Left and does not unlock', () {
    fakeAsync((async) {
      final repo = _FakePaywallRepository()
        ..purchaseResult = const Left(UnexpectedFailure('boom'));
      final proPaywall = _build(
        FakeSessionRepository(current: testSession('s1')),
        repo,
      );
      Either<Failure, Unit>? result;

      proPaywall.purchase().then((value) => result = value);
      async.elapse(const Duration(seconds: 1));

      expect(result?.isLeft(), isTrue);
      expect(proPaywall.isUnlocked, isFalse);
      expect(proPaywall.isPurchasing, isFalse);
      proPaywall.dispose();
    });
  });

  test('a second tap while purchasing is ignored', () {
    fakeAsync((async) {
      final repo = _FakePaywallRepository();
      final proPaywall = _build(
        FakeSessionRepository(current: testSession('s1')),
        repo,
      );
      Either<Failure, Unit>? second = const Right(unit);

      proPaywall.purchase();
      proPaywall.purchase().then((value) => second = value);
      async.elapse(const Duration(seconds: 1));

      expect(second, isNull);
      expect(repo.purchaseCalls, 1);
      expect(proPaywall.isUnlocked, isTrue);
      proPaywall.dispose();
    });
  });

  test('never asks the server while offline; checks again only online', () {
    fakeAsync((async) {
      final sessions = FakeSessionRepository();
      final repo = _FakePaywallRepository();
      final proPaywall = _build(sessions, repo);

      async.elapse(const Duration(minutes: 30));
      expect(repo.statusCalls, 0);

      sessions.start(testSession('s1'));
      async.elapse(const Duration(minutes: 11));
      expect(repo.statusCalls, 3); // subito, poi a 5 e 10 minuti

      sessions.end();
      async.elapse(const Duration(minutes: 30));
      expect(repo.statusCalls, 3);
      proPaywall.dispose();
    });
  });

  testWidgets('a failed purchase shows an error, never "unlocked"', (
    tester,
  ) async {
    final repo = _FakePaywallRepository()
      ..purchaseResult = const Left(UnexpectedFailure('boom'));
    // Offline: niente controllo periodico (e nessun timer da attendere).
    final proPaywall = _build(FakeSessionRepository(), repo);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: proPaywall,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: CmpPaywallBanner()),
        ),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.text(l10n.unlock_eur_1));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.pay_eur_1));
    await tester.pump();
    // Durante l'acquisto il bottone è disattivato, con un indicatore.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text(l10n.purchase_failed), findsOneWidget);
    expect(find.text(l10n.unlocked_for_the_next_2_hours), findsNothing);

    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });
}
