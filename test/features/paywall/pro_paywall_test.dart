import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:provider/provider.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/paywall/data/datasources/store_billing_data_source.dart';
import 'package:threemojo_app/features/paywall/data/datasources/store_billing_data_source_fake_impl.dart';
import 'package:threemojo_app/features/paywall/data/datasources/store_billing_data_source_impl.dart';
import 'package:threemojo_app/features/paywall/domain/entities/unlock_purchase_result.dart';
import 'package:threemojo_app/features/paywall/domain/repositories/paywall_repository.dart';
import 'package:threemojo_app/features/paywall/presentation/providers/pro_paywall.dart';
import 'package:threemojo_app/features/paywall/presentation/widgets/cmp_paywall_banner.dart';
import 'package:threemojo_app/features/paywall/presentation/widgets/cmp_unlock_chip.dart';
import 'package:threemojo_app/features/paywall/presentation/widgets/cmp_unlock_expired_listener.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import '../../support/fake_paywall.dart';
import '../../support/fake_repositories.dart';

/// Il server finto: vedi `FakePaywallServer`.
typedef _FakePaywallRepository = FakePaywallServer;

ProPaywall _build(
  FakeSessionRepository sessions,
  PaywallRepository repo, {
  DateTime Function()? now,
  StoreBillingDataSource? store,
}) =>
    buildProPaywall(sessions: sessions, paywall: repo, now: now, store: store);

final _start = DateTime(2026, 10, 22, 21, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed purchase returns Left and does not unlock', () {
    fakeAsync((async) {
      DateTime now() => _start.add(async.elapsed);
      final repo = _FakePaywallRepository(now)
        ..redeemResult = const Left(UnexpectedFailure('boom'));
      final proPaywall = _build(
        FakeSessionRepository(current: testSession('s1')),
        repo,
        now: now,
      );
      Either<Failure, UnlockPurchaseResult>? result;

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
      DateTime now() => _start.add(async.elapsed);
      final repo = _FakePaywallRepository(now);
      final proPaywall = _build(
        FakeSessionRepository(current: testSession('s1')),
        repo,
        now: now,
      );
      Either<Failure, UnlockPurchaseResult>? second = const Right(
        UnlockPurchasePending(),
      );

      proPaywall.purchase();
      proPaywall.purchase().then((value) => second = value);
      async.elapse(const Duration(seconds: 1));

      expect(second, isNull);
      expect(repo.redeemCalls, 1);
      expect(proPaywall.isUnlocked, isTrue);
      proPaywall.dispose();
    });
  });

  test('never asks the server while offline; checks again only online', () {
    fakeAsync((async) {
      DateTime now() => _start.add(async.elapsed);
      final sessions = FakeSessionRepository();
      final repo = _FakePaywallRepository(now);
      final proPaywall = _build(sessions, repo, now: now);

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

  test('after a purchase the time left changes once a minute, on the minute '
      'boundary — never more often', () {
    fakeAsync((async) {
      DateTime now() => _start.add(async.elapsed);
      final repo = _FakePaywallRepository(now);
      final proPaywall = _build(
        FakeSessionRepository(current: testSession('s1')),
        repo,
        now: now,
      );
      async.flushMicrotasks();
      // Acquisto a metà di un secondo qualsiasi: 21:00:20.
      async.elapse(const Duration(seconds: 20));
      proPaywall.purchase();
      async.elapse(const Duration(milliseconds: 800));
      expect(proPaywall.expiresAt, DateTime(2026, 10, 22, 23, 0, 20, 800));
      expect(proPaywall.timeLeft?.wholeMinutes, 119);

      var notifications = 0;
      proPaywall.addListener(() => notifications++);
      // 21:00:20.8 → 21:10:20.8: 10 confini di minuto, più 2 controlli
      // periodici dello stato (a 5 e 10 minuti dallo Start) che non
      // cambiano nulla di visibile.
      async.elapse(const Duration(minutes: 10));

      expect(proPaywall.timeLeft?.wholeMinutes, 109);
      expect(notifications, 10);
      expect(async.pendingTimers.length, 2); // il minuto + il controllo
      proPaywall.dispose();
    });
  });

  test('at the expiry: chip gone, one expiration event, the server is asked '
      'again', () {
    fakeAsync((async) {
      DateTime now() => _start.add(async.elapsed);
      final repo = _FakePaywallRepository(now)
        ..serverExpiresAt = _start.add(const Duration(minutes: 3, seconds: 30));
      final sessions = FakeSessionRepository(current: testSession('s1'));
      final proPaywall = _build(sessions, repo, now: now);
      var expirations = 0;
      proPaywall.expirations.listen((_) => expirations++);
      async.flushMicrotasks();
      expect(proPaywall.timeLeft?.wholeMinutes, 3);
      expect(proPaywall.timeLeft?.isEndingSoon, isTrue);

      async.elapse(const Duration(minutes: 3, seconds: 29));
      expect(proPaywall.timeLeft?.wholeMinutes, 0); // "meno di un minuto"
      expect(proPaywall.isUnlocked, isTrue);
      final callsBefore = repo.statusCalls;

      async.elapse(const Duration(seconds: 1));
      expect(proPaywall.isUnlocked, isFalse);
      expect(proPaywall.expiresAt, isNull);
      expect(expirations, 1);
      expect(repo.statusCalls, callsBefore + 1);

      // Nessun timer del tempo residuo resta acceso: solo il controllo
      // periodico dello stato, e nessun altro evento.
      async.elapse(const Duration(hours: 1));
      expect(expirations, 1);
      sessions.end();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
      proPaywall.dispose();
    });
  });

  test('every status check realigns the expiry to the server', () {
    fakeAsync((async) {
      DateTime now() => _start.add(async.elapsed);
      final repo = _FakePaywallRepository(now)
        ..serverExpiresAt = _start.add(const Duration(hours: 1));
      final proPaywall = _build(
        FakeSessionRepository(current: testSession('s1')),
        repo,
        now: now,
      );
      async.flushMicrotasks();
      expect(proPaywall.expiresAt, _start.add(const Duration(hours: 1)));

      // Il server la vede diversamente (es. il telefono era in pausa):
      // al controllo successivo vale la sua.
      repo.serverExpiresAt = _start.add(const Duration(minutes: 40));
      async.elapse(const Duration(minutes: 5));

      expect(proPaywall.expiresAt, _start.add(const Duration(minutes: 40)));
      expect(proPaywall.timeLeft?.wholeMinutes, 34);
      proPaywall.dispose();
    });
  });

  test('the server saying it is over ends it too (one event); a failed check '
      'changes nothing', () {
    fakeAsync((async) {
      DateTime now() => _start.add(async.elapsed);
      final repo = _FakePaywallRepository(now)
        ..serverExpiresAt = _start.add(const Duration(hours: 1));
      final proPaywall = _build(
        FakeSessionRepository(current: testSession('s1')),
        repo,
        now: now,
      );
      var expirations = 0;
      proPaywall.expirations.listen((_) => expirations++);
      async.flushMicrotasks();

      repo.statusFails = true;
      async.elapse(const Duration(minutes: 5));
      expect(proPaywall.isUnlocked, isTrue);

      // Es. server riavviato: lo sblocco non c'è più.
      repo
        ..statusFails = false
        ..serverExpiresAt = null;
      async.elapse(const Duration(minutes: 5));
      expect(proPaywall.isUnlocked, isFalse);
      expect(expirations, 1);
      proPaywall.dispose();
    });
  });

  test('offline: no timer at all; an unlock that ended meanwhile is told '
      'once at the next Start', () {
    fakeAsync((async) {
      DateTime now() => _start.add(async.elapsed);
      final repo = _FakePaywallRepository(now)
        ..serverExpiresAt = _start.add(const Duration(minutes: 30));
      final sessions = FakeSessionRepository(current: testSession('s1'));
      final proPaywall = _build(sessions, repo, now: now);
      var expirations = 0;
      proPaywall.expirations.listen((_) => expirations++);
      async.flushMicrotasks();
      expect(proPaywall.isUnlocked, isTrue);

      sessions.end();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);

      async.elapse(const Duration(hours: 1));
      expect(expirations, 0);

      sessions.start(testSession('s2'));
      async.flushMicrotasks();
      expect(proPaywall.isUnlocked, isFalse);
      expect(expirations, 1);
      proPaywall.dispose();
    });
  });

  test('back in the foreground the time left is recomputed at once, '
      'without asking the server', () {
    fakeAsync((async) {
      var clock = _start;
      DateTime now() => clock;
      final repo = _FakePaywallRepository(now)
        ..serverExpiresAt = _start.add(const Duration(hours: 1));
      final proPaywall = _build(
        FakeSessionRepository(current: testSession('s1')),
        repo,
        now: now,
      );
      async.flushMicrotasks();
      expect(proPaywall.timeLeft?.wholeMinutes, 59);
      final calls = repo.statusCalls;

      // In background i timer possono restare fermi mentre l'ora corre.
      clock = clock.add(const Duration(minutes: 25));
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );

      expect(proPaywall.timeLeft?.wholeMinutes, 34);
      expect(repo.statusCalls, calls);
      proPaywall.dispose();
    });
  });

  Future<AppLocalizations> pumpBanner(
    WidgetTester tester,
    ProPaywall proPaywall,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: proPaywall,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CmpUnlockExpiredListener(
            child: Scaffold(body: CmpPaywallBanner()),
          ),
        ),
      ),
    );
    // Il prezzo del negozio arriva subito dopo.
    await tester.pump();
    return AppLocalizations.delegate.load(const Locale('en'));
  }

  /// Fa scattare i timer a zero del negozio finto e le risposte.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> buyFromBanner(WidgetTester tester, AppLocalizations l10n) async {
    await tester.tap(find.text(l10n.unlock_eur_1));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.pay_eur_1));
    await tester.pump();
  }

  testWidgets('a store error shows an error, never "unlocked"', (tester) async {
    // Offline: niente controllo periodico (e nessun timer da attendere).
    final proPaywall = _build(
      FakeSessionRepository(),
      _FakePaywallRepository(),
      store: fakeStore(
        outcome: FakeStoreOutcome.error,
        sheetDelay: const Duration(milliseconds: 800),
      ),
    );
    final l10n = await pumpBanner(tester, proPaywall);

    await buyFromBanner(tester, l10n);
    // Durante l'acquisto il bottone è disattivato, con un indicatore.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text(l10n.purchase_failed), findsOneWidget);
    expect(find.text(l10n.unlocked_for_the_next_2_hours), findsNothing);

    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });

  testWidgets('the simulated store says so: price 1 € and "nothing is '
      'charged"', (tester) async {
    final proPaywall = _build(
      FakeSessionRepository(),
      _FakePaywallRepository(),
    );
    final l10n = await pumpBanner(tester, proPaywall);

    await tester.tap(find.text(l10n.unlock_eur_1));
    await tester.pumpAndSettle();

    expect(
      find.text(
        l10n.unlock_every_nearby_profile_for_the_next_2_hours_for_eur_1,
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.pay_eur_1), findsOneWidget);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });

  testWidgets('canceled in the store: no error, nothing unlocked', (
    tester,
  ) async {
    final repo = _FakePaywallRepository();
    final proPaywall = _build(
      FakeSessionRepository(),
      repo,
      store: fakeStore(outcome: FakeStoreOutcome.canceled),
    );
    final l10n = await pumpBanner(tester, proPaywall);

    await buyFromBanner(tester, l10n);
    await settle(tester);

    expect(find.byType(SnackBar), findsNothing);
    expect(proPaywall.isUnlocked, isFalse);
    expect(proPaywall.isPurchasing, isFalse);
    expect(repo.redeemCalls, 0);
    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });

  testWidgets('a pending payment says "awaiting confirmation", then unlocks '
      'by itself when the store confirms', (tester) async {
    final proPaywall = _build(
      FakeSessionRepository(),
      _FakePaywallRepository(),
      store: fakeStore(
        outcome: FakeStoreOutcome.pending,
        approvalDelay: const Duration(seconds: 5),
      ),
    );
    final l10n = await pumpBanner(tester, proPaywall);

    await buyFromBanner(tester, l10n);
    await settle(tester);

    expect(proPaywall.isPaymentPending, isTrue);
    expect(find.text(l10n.payment_pending_confirmation), findsWidgets);
    expect(proPaywall.isUnlocked, isFalse);

    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    expect(proPaywall.isUnlocked, isTrue);
    expect(proPaywall.isPaymentPending, isFalse);
    // Dopo la snackbar "in attesa" (in coda), quella dello sblocco.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l10n.unlocked_for_the_next_2_hours), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });

  testWidgets('paid but the server is unreachable: "payment received", the '
      'purchase stays open and unlocks at the next Start', (tester) async {
    final sessions = FakeSessionRepository();
    final repo = _FakePaywallRepository()
      ..redeemResult = const Left(ConnectionFailure('down'));
    final store = fakeStore();
    final proPaywall = _build(sessions, repo, store: store);
    final l10n = await pumpBanner(tester, proPaywall);

    await buyFromBanner(tester, l10n);
    await settle(tester);

    expect(find.text(l10n.unlock_delivery_delayed), findsOneWidget);
    expect(store.knownUnfinishedPurchases, hasLength(1));
    expect(store.completed, isEmpty);

    repo.redeemResult = null;
    sessions.start(testSession('s1'));
    await settle(tester);

    expect(proPaywall.isUnlocked, isTrue);
    expect(store.completed, hasLength(1));
    sessions.end();
    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });

  testWidgets('without a store (release without configuration) the button '
      'is "Not available" and payment cannot start', (tester) async {
    final repo = _FakePaywallRepository();
    final proPaywall = _build(
      FakeSessionRepository(),
      repo,
      store: StoreBillingDataSourceImpl(productId: null),
    );
    final l10n = await pumpBanner(tester, proPaywall);

    expect(proPaywall.offerState, UnlockOfferState.unavailable);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text(l10n.unlock_unavailable), findsOneWidget);
    expect(find.text(l10n.unlock_eur_1), findsNothing);

    // Anche da una foto bloccata: nessuna finestra, solo il perché.
    showPaywallConfirmDialog(tester.element(find.byType(CmpPaywallBanner)));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(l10n.unlock_store_unavailable), findsOneWidget);
    expect(repo.redeemCalls, 0);

    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });

  testWidgets('as today with the simulated store: banner → pay → "Sbloccato" '
      'chip, and the store purchase is completed', (tester) async {
    final sessions = FakeSessionRepository(current: testSession('s1'));
    final store = fakeStore(sheetDelay: const Duration(milliseconds: 800));
    final proPaywall = _build(sessions, _FakePaywallRepository(), store: store);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: proPaywall,
        child: MaterialApp(
          locale: const Locale('it'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer<ProPaywall>(
              builder: (context, paywall, _) => Column(
                children: [
                  const CmpUnlockChip(),
                  if (!paywall.isUnlocked) const CmpPaywallBanner(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('it'));

    await tester.tap(find.text(l10n.unlock_eur_1));
    await tester.pumpAndSettle();
    expect(find.textContaining('pagamento finto'), findsOneWidget);
    await tester.tap(find.text(l10n.pay_eur_1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    await tester.pump();

    expect(find.text('Sbloccato · ancora 1 h 59 min'), findsOneWidget);
    expect(find.byType(CmpPaywallBanner), findsNothing);
    expect(find.text(l10n.unlocked_for_the_next_2_hours), findsOneWidget);
    expect(store.completed, hasLength(1));

    sessions.end();
    await tester.pumpWidget(const SizedBox());
    proPaywall.dispose();
  });
}
