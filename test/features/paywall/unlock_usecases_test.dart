import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/usecases/usecase.dart';
import 'package:threemojo_app/features/paywall/data/repositories/store_repository_impl.dart';
import 'package:threemojo_app/features/paywall/domain/entities/store_purchase.dart';
import 'package:threemojo_app/features/paywall/domain/entities/unlock_purchase_result.dart';
import 'package:threemojo_app/features/paywall/domain/entities/unlock_status.dart';
import 'package:threemojo_app/features/paywall/domain/repositories/paywall_repository.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/get_unlock_status_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/get_unlock_time_left_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/purchase_unlock_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/redeem_store_purchase_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/resolve_unlock_expiry_usecase.dart';

import '../../support/fake_paywall.dart';

class _FakePaywallRepository implements PaywallRepository {
  Either<Failure, Duration> remaining = const Right(Duration.zero);
  Either<Failure, Duration> purchased = const Right(Duration(hours: 2));

  @override
  Future<Either<Failure, Duration>> getUnlockTimeRemaining() async => remaining;

  @override
  Future<Either<Failure, Duration>> redeemPurchase(
    StorePurchase purchase,
  ) async => purchased;
}

void main() {
  final now = DateTime(2026, 10, 22, 21, 33, 20);

  group('ResolveUnlockExpiryUseCase', () {
    test(
      'expiry = phone time at the answer + what the server says is left',
      () {
        final resolve = ResolveUnlockExpiryUseCase(now: () => now);

        expect(
          resolve(const Duration(hours: 1, minutes: 41, seconds: 40)),
          UnlockStatus.until(DateTime(2026, 10, 22, 23, 15)),
        );
      },
    );

    test('nothing left (or a negative number) means locked', () {
      final resolve = ResolveUnlockExpiryUseCase(now: () => now);

      expect(resolve(Duration.zero), const UnlockStatus.locked());
      expect(resolve(const Duration(seconds: -5)), const UnlockStatus.locked());
    });

    test('a phone clock hours off does not change how much time is left', () {
      // Telefono indietro di 3 ore: la scadenza "locale" si sposta con lui,
      // il residuo misurato con lo stesso orologio resta quello del server.
      final wrongNow = now.subtract(const Duration(hours: 3));
      final status = ResolveUnlockExpiryUseCase(now: () => wrongNow)(
        const Duration(minutes: 30),
      );

      final timeLeft = GetUnlockTimeLeftUseCase(now: () => wrongNow)(status);

      expect(timeLeft?.wholeMinutes, 29);
      expect(timeLeft?.nextChangeIn, const Duration(minutes: 1));
    });
  });

  group('GetUnlockStatusUseCase / PurchaseUnlockUseCase', () {
    test('turn the server remaining time into an expiry', () async {
      final repo = _FakePaywallRepository()
        ..remaining = const Right(Duration(minutes: 90));
      final resolve = ResolveUnlockExpiryUseCase(now: () => now);

      final status = await GetUnlockStatusUseCase(
        repo,
        resolveUnlockExpiryUseCase: resolve,
      )(const NoParams());
      final store = StoreRepositoryImpl(fakeStore());
      final purchased = await PurchaseUnlockUseCase(
        storeRepository: store,
        redeemStorePurchaseUseCase: RedeemStorePurchaseUseCase(
          paywallRepository: repo,
          storeRepository: store,
          resolveUnlockExpiryUseCase: resolve,
        ),
      )(const NoParams());

      expect(
        status,
        Right(UnlockStatus.until(now.add(const Duration(minutes: 90)))),
      );
      expect(
        purchased,
        Right<Failure, UnlockPurchaseResult>(
          UnlockPurchased(
            UnlockStatus.until(now.add(const Duration(hours: 2))),
          ),
        ),
      );
    });

    test('no time left is locked; a failure stays a failure', () async {
      final repo = _FakePaywallRepository();
      final getStatus = GetUnlockStatusUseCase(
        repo,
        resolveUnlockExpiryUseCase: ResolveUnlockExpiryUseCase(now: () => now),
      );

      expect(
        await getStatus(const NoParams()),
        const Right<Failure, UnlockStatus>(UnlockStatus.locked()),
      );

      repo.remaining = const Left(UnexpectedFailure('down'));
      expect((await getStatus(const NoParams())).isLeft(), isTrue);
    });
  });

  group('GetUnlockTimeLeftUseCase', () {
    final expiresAt = DateTime(2026, 10, 22, 23, 15);
    UnlockStatus status() => UnlockStatus.until(expiresAt);

    test('whole minutes, rounded down, never seconds', () {
      final timeLeft = GetUnlockTimeLeftUseCase(
        now: () => expiresAt.subtract(
          const Duration(hours: 1, minutes: 42, seconds: 30),
        ),
      )(status())!;

      expect(timeLeft.wholeMinutes, 102);
      expect(timeLeft.hours, 1);
      expect(timeLeft.minutes, 42);
      expect(timeLeft.isEndingSoon, isFalse);
      // Il prossimo cambio è sul confine del minuto: fra 30 s.
      expect(timeLeft.nextChangeIn, const Duration(seconds: 30));
    });

    test('on an exact minute it already shows the next one down', () {
      final timeLeft = GetUnlockTimeLeftUseCase(
        now: () => expiresAt.subtract(const Duration(minutes: 42)),
      )(status())!;

      expect(timeLeft.wholeMinutes, 41);
      expect(timeLeft.nextChangeIn, const Duration(minutes: 1));
    });

    test('the last minute is 0 ("less than a minute") until the expiry', () {
      final timeLeft = GetUnlockTimeLeftUseCase(
        now: () => expiresAt.subtract(const Duration(seconds: 59)),
      )(status())!;

      expect(timeLeft.wholeMinutes, 0);
      expect(timeLeft.isEndingSoon, isTrue);
      expect(timeLeft.nextChangeIn, const Duration(seconds: 59));
    });

    test('ending soon only in the last 10 minutes', () {
      GetUnlockTimeLeftUseCase at(Duration before) =>
          GetUnlockTimeLeftUseCase(now: () => expiresAt.subtract(before));

      expect(
        at(const Duration(minutes: 10, seconds: 1))(status())!.isEndingSoon,
        isFalse,
      );
      expect(at(const Duration(minutes: 10))(status())!.isEndingSoon, isTrue);
    });

    test('expired or locked: nothing to show', () {
      expect(GetUnlockTimeLeftUseCase(now: () => expiresAt)(status()), isNull);
      expect(
        GetUnlockTimeLeftUseCase(
          now: () => expiresAt.add(const Duration(minutes: 1)),
        )(status()),
        isNull,
      );
      expect(
        GetUnlockTimeLeftUseCase(now: () => now)(const UnlockStatus.locked()),
        isNull,
      );
    });
  });
}
