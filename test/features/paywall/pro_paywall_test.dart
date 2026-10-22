import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:provider/provider.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/paywall/domain/repositories/paywall_repository.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/get_unlock_status_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/get_unlock_time_left_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/purchase_unlock_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/resolve_unlock_expiry_usecase.dart';
import 'package:threemojo_app/features/paywall/presentation/providers/pro_paywall.dart';
import 'package:threemojo_app/features/paywall/presentation/widgets/cmp_paywall_banner.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import '../../support/fake_repositories.dart';

/// Il server finto: tiene la scadenza sul **suo** orologio ([now]) e
/// risponde col residuo, come `PaywallStore`.
class _FakePaywallRepository implements PaywallRepository {
  _FakePaywallRepository(this.now);

  final DateTime Function() now;
  DateTime? serverExpiresAt;
  Either<Failure, Duration>? purchaseFailure;
  bool statusFails = false;
  int statusCalls = 0;
  int purchaseCalls = 0;

  Duration get _remaining {
    final expiresAt = serverExpiresAt;
    if (expiresAt == null) return Duration.zero;
    final remaining = expiresAt.difference(now());
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  @override
  Future<Either<Failure, Duration>> getUnlockTimeRemaining() async {
    statusCalls++;
    if (statusFails) return const Left(UnexpectedFailure('down'));
    return Right(_remaining);
  }

  @override
  Future<Either<Failure, Duration>> purchaseUnlock() async {
    purchaseCalls++;
    final failure = purchaseFailure;
    if (failure != null) return failure;
    serverExpiresAt = now().add(const Duration(hours: 2));
    return Right(_remaining);
  }
}

ProPaywall _build(
  FakeSessionRepository sessions,
  PaywallRepository repo, {
  DateTime Function()? now,
}) {
  final resolve = ResolveUnlockExpiryUseCase(now: now);
  return ProPaywall(
    watchSessionUseCase: WatchSessionUseCase(sessions),
    getUnlockStatusUseCase: GetUnlockStatusUseCase(
      repo,
      resolveUnlockExpiryUseCase: resolve,
    ),
    purchaseUnlockUseCase: PurchaseUnlockUseCase(
      repo,
      resolveUnlockExpiryUseCase: resolve,
    ),
    getUnlockTimeLeftUseCase: GetUnlockTimeLeftUseCase(now: now),
  );
}

final _start = DateTime(2026, 10, 22, 21, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed purchase returns Left and does not unlock', () {
    fakeAsync((async) {
      DateTime now() => _start.add(async.elapsed);
      final repo = _FakePaywallRepository(now)
        ..purchaseFailure = const Left(UnexpectedFailure('boom'));
      final proPaywall = _build(
        FakeSessionRepository(current: testSession('s1')),
        repo,
        now: now,
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
      DateTime now() => _start.add(async.elapsed);
      final repo = _FakePaywallRepository(now);
      final proPaywall = _build(
        FakeSessionRepository(current: testSession('s1')),
        repo,
        now: now,
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

  testWidgets('a failed purchase shows an error, never "unlocked"', (
    tester,
  ) async {
    final repo = _FakePaywallRepository(DateTime.now)
      ..purchaseFailure = const Left(UnexpectedFailure('boom'));
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
