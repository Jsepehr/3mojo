import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/config/store_config.dart';
import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/usecases/usecase.dart';
import 'package:threemojo_app/features/paywall/data/datasources/store_billing_data_source_fake_impl.dart';
import 'package:threemojo_app/features/paywall/data/datasources/store_billing_data_source_impl.dart';
import 'package:threemojo_app/features/paywall/data/repositories/store_repository_impl.dart';
import 'package:threemojo_app/features/paywall/domain/entities/store_purchase.dart';
import 'package:threemojo_app/features/paywall/domain/entities/unlock_offer.dart';
import 'package:threemojo_app/features/paywall/domain/entities/unlock_purchase_result.dart';
import 'package:threemojo_app/features/paywall/domain/entities/unlock_status.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/get_unlock_offer_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/purchase_unlock_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/redeem_store_purchase_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/resolve_unlock_expiry_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/retry_unfinished_purchases_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/watch_unfinished_purchases_usecase.dart';

import '../../support/fake_paywall.dart';

/// L'acquisto dall'inizio alla fine con il **negozio simulato vero**
/// (`StoreBillingDataSourceFakeImpl` + `StoreRepositoryImpl`) e il server
/// finto (`FakePaywallServer`).
class _Flow {
  _Flow({
    FakeStoreOutcome outcome = FakeStoreOutcome.success,
    Iterable<StorePurchase> unfinishedAtStartup = const [],
    Duration approvalDelay = const Duration(milliseconds: 50),
  }) : store = fakeStore(
         outcome: outcome,
         approvalDelay: approvalDelay,
         unfinishedAtStartup: unfinishedAtStartup,
       ) {
    final storeRepository = StoreRepositoryImpl(store);
    redeem = RedeemStorePurchaseUseCase(
      paywallRepository: server,
      storeRepository: storeRepository,
      resolveUnlockExpiryUseCase: ResolveUnlockExpiryUseCase(now: () => now),
    );
    purchase = PurchaseUnlockUseCase(
      storeRepository: storeRepository,
      redeemStorePurchaseUseCase: redeem,
    );
    watch = WatchUnfinishedPurchasesUseCase(
      storeRepository: storeRepository,
      redeemStorePurchaseUseCase: redeem,
    );
    retry = RetryUnfinishedPurchasesUseCase(
      storeRepository: storeRepository,
      redeemStorePurchaseUseCase: redeem,
    );
    offer = GetUnlockOfferUseCase(storeRepository);
  }

  static final now = DateTime(2026, 10, 23, 21);
  final FakePaywallServer server = FakePaywallServer(() => now);
  final StoreBillingDataSourceFakeImpl store;
  late final RedeemStorePurchaseUseCase redeem;
  late final PurchaseUnlockUseCase purchase;
  late final WatchUnfinishedPurchasesUseCase watch;
  late final RetryUnfinishedPurchasesUseCase retry;
  late final GetUnlockOfferUseCase offer;

  Future<Either<Failure, UnlockPurchaseResult>> buy() =>
      purchase(const NoParams());
}

final _unlocked = Right<Failure, UnlockPurchaseResult>(
  UnlockPurchased(UnlockStatus.until(_Flow.now.add(const Duration(hours: 2)))),
);

void main() {
  group('PurchaseUnlockUseCase with the simulated store', () {
    test(
      'success: verified by the server, then completed in the store',
      () async {
        final flow = _Flow();

        expect(await flow.buy(), _unlocked);
        expect(flow.server.redeemCalls, 1);
        expect(flow.store.completed, hasLength(1));
        expect(flow.store.knownUnfinishedPurchases, isEmpty);
      },
    );

    test(
      'the store purchase is NOT completed before the server confirms',
      () async {
        final flow = _Flow();
        flow.server.redeemGate = Completer<void>();

        final result = flow.buy();
        await pumpEventQueue();
        expect(flow.server.redeemCalls, 1);
        expect(flow.store.completed, isEmpty);
        expect(flow.store.knownUnfinishedPurchases, hasLength(1));

        flow.server.redeemGate!.complete();
        expect(await result, _unlocked);
        expect(flow.store.completed, hasLength(1));
      },
    );

    test('canceled in the store: a silent failure, nothing redeemed', () async {
      final flow = _Flow(outcome: FakeStoreOutcome.canceled);

      expect(await flow.buy(), const Left(PurchaseCanceledFailure()));
      expect(flow.server.redeemCalls, 0);
    });

    test('store error: a typed failure, nothing redeemed', () async {
      final flow = _Flow(outcome: FakeStoreOutcome.error);

      final result = await flow.buy();

      expect(result.getLeft().toNullable(), isA<StorePurchaseFailure>());
      expect(flow.server.redeemCalls, 0);
    });

    test('pending: "awaiting", then the confirmed purchase is redeemed by '
        'itself from the unfinished stream', () async {
      final flow = _Flow(outcome: FakeStoreOutcome.pending);
      final delivered = <Either<Failure, UnlockStatus>>[];
      final subscription = flow.watch().listen(delivered.add);

      expect(
        await flow.buy(),
        const Right<Failure, UnlockPurchaseResult>(UnlockPurchasePending()),
      );
      expect(flow.server.redeemCalls, 0);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await pumpEventQueue();

      expect(delivered, hasLength(1));
      expect(delivered.single.isRight(), isTrue);
      expect(flow.store.completed, hasLength(1));
      await subscription.cancel();
    });

    test('server unreachable: paid but not delivered yet, the purchase stays '
        'open; the retry delivers it and only then completes it', () async {
      final flow = _Flow();
      flow.server.redeemResult = const Left(ConnectionFailure('down'));

      expect(await flow.buy(), const Left(UnlockNotDeliveredYetFailure()));
      expect(flow.store.completed, isEmpty);
      expect(flow.store.knownUnfinishedPurchases, hasLength(1));

      flow.server.redeemResult = null;
      final retried = await flow.retry();

      expect(retried.single.isRight(), isTrue);
      expect(flow.store.completed, hasLength(1));
      expect(flow.store.knownUnfinishedPurchases, isEmpty);
    });

    test('no double charge: with a paid purchase still open, buying again '
        'redeems that one instead of opening the store', () async {
      final flow = _Flow();
      flow.server.redeemResult = const Left(ConnectionFailure('down'));
      await flow.buy();

      // Server ancora giù: nessuna nuova finestra del negozio.
      expect(await flow.buy(), const Left(UnlockNotDeliveredYetFailure()));
      expect(flow.store.knownUnfinishedPurchases, hasLength(1));

      flow.server.redeemResult = null;
      expect(await flow.buy(), _unlocked);
      expect(flow.server.redeemed, hasLength(1));
      expect(flow.store.completed, hasLength(1));
    });

    test('rejected by the server after checking with the store: no unlock '
        'and the purchase is not completed', () async {
      final flow = _Flow();
      flow.server.redeemResult = const Left(
        PurchaseNotVerifiedFailure('invalidReceipt'),
      );

      expect(
        await flow.buy(),
        const Left(PurchaseNotVerifiedFailure('invalidReceipt')),
      );
      expect(flow.store.completed, isEmpty);
    });

    test(
      'already redeemed (unlock over): completed, since it was delivered',
      () async {
        final flow = _Flow();
        flow.server.redeemResult = const Left(PurchaseAlreadyRedeemedFailure());

        expect(await flow.buy(), const Left(PurchaseAlreadyRedeemedFailure()));
        expect(flow.store.completed, hasLength(1));
      },
    );
  });

  group('purchases left open by a previous run', () {
    test(
      'are redeemed at startup from the unfinished stream, then completed',
      () async {
        final leftOver = StoreBillingDataSourceFakeImpl.newPurchase();
        final flow = _Flow(unfinishedAtStartup: [leftOver]);

        final first = await flow.watch().first;

        expect(first.isRight(), isTrue);
        expect(flow.server.redeemed, [leftOver]);
        expect(flow.store.completed, [leftOver]);
      },
    );

    test('the same purchase from the stream and from a retry is redeemed '
        'only once at a time', () async {
      final leftOver = StoreBillingDataSourceFakeImpl.newPurchase();
      final flow = _Flow(unfinishedAtStartup: [leftOver]);
      flow.server.redeemGate = Completer<void>();

      final fromStream = flow.watch().first;
      await pumpEventQueue();
      final fromRetry = flow.retry();
      await pumpEventQueue();
      flow.server.redeemGate!.complete();

      expect((await fromStream).isRight(), isTrue);
      expect((await fromRetry).single.isRight(), isTrue);
      expect(flow.server.redeemCalls, 1);
    });
  });

  group('which store', () {
    test('the simulated store shows the configured price (1 €)', () async {
      expect(
        await _Flow().offer(const NoParams()),
        const Right<Failure, UnlockOffer>(UnlockOffer.simulated()),
      );
    });

    test('placeholder product IDs are not a configuration', () {
      expect(StoreConfig.isConfigured(StoreConfig.iosUnlockProductId), isFalse);
      expect(
        StoreConfig.isConfigured(StoreConfig.androidUnlockProductId),
        isFalse,
      );
      expect(StoreConfig.isConfigured('it.ameol.raen.unlock_2h'), isTrue);
      expect(
        StoreConfig.unlockProductIdFor(TargetPlatform.iOS, isWeb: false),
        isNull,
      );
      expect(
        StoreConfig.unlockProductIdFor(TargetPlatform.android, isWeb: true),
        isNull,
      );
    });

    test('debug without real payments → simulated; release without '
        'configuration → unavailable, never free', () {
      StoreMode mode({
        required bool debug,
        required bool real,
        String? productId,
      }) => StoreConfig.resolveMode(
        debugBuild: debug,
        realPaymentsEnabled: real,
        productId: productId,
      );

      expect(mode(debug: true, real: false), StoreMode.fake);
      expect(mode(debug: false, real: false), StoreMode.unavailable);
      expect(
        mode(debug: false, real: false, productId: 'p'),
        StoreMode.unavailable,
      );
      expect(mode(debug: false, real: true), StoreMode.unavailable);
      expect(mode(debug: true, real: true), StoreMode.unavailable);
      expect(mode(debug: false, real: true, productId: 'p'), StoreMode.real);
      expect(mode(debug: true, real: true, productId: 'p'), StoreMode.real);
    });

    test('this test build has real payments off: the simulated store', () {
      expect(StoreConfig.realPaymentsEnabled, isFalse);
      expect(StoreConfig.mode, StoreMode.fake);
    });

    test('release without configuration: the purchase cannot start and '
        'nothing reaches the server', () async {
      final store = StoreRepositoryImpl(
        StoreBillingDataSourceImpl(productId: null),
      );
      final server = FakePaywallServer();
      final purchase = PurchaseUnlockUseCase(
        storeRepository: store,
        redeemStorePurchaseUseCase: RedeemStorePurchaseUseCase(
          paywallRepository: server,
          storeRepository: store,
        ),
      );

      expect(
        (await GetUnlockOfferUseCase(store)(
          const NoParams(),
        )).getLeft().toNullable(),
        isA<StoreUnavailableFailure>(),
      );
      expect(
        (await purchase(const NoParams())).getLeft().toNullable(),
        isA<StoreUnavailableFailure>(),
      );
      expect(server.redeemCalls, 0);
    });
  });
}
