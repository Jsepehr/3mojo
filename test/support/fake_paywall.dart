import 'dart:async';

import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/paywall/data/datasources/store_billing_data_source.dart';
import 'package:threemojo_app/features/paywall/data/datasources/store_billing_data_source_fake_impl.dart';
import 'package:threemojo_app/features/paywall/data/repositories/store_repository_impl.dart';
import 'package:threemojo_app/features/paywall/domain/entities/store_purchase.dart';
import 'package:threemojo_app/features/paywall/domain/repositories/paywall_repository.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/get_unlock_offer_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/get_unlock_status_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/get_unlock_time_left_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/purchase_unlock_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/redeem_store_purchase_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/resolve_unlock_expiry_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/retry_unfinished_purchases_usecase.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/watch_unfinished_purchases_usecase.dart';
import 'package:threemojo_app/features/paywall/presentation/providers/pro_paywall.dart';
import 'package:threemojo_app/features/session/domain/repositories/session_repository.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';

/// Il server del paywall finto: tiene la scadenza sul **suo** orologio
/// ([now]) e risponde col residuo, come `PaywallStore`; riscatta ogni
/// acquisto una volta (lo stesso ridà lo stesso sblocco), come
/// `UnlockPurchaseService`.
class FakePaywallServer implements PaywallRepository {
  FakePaywallServer([DateTime Function()? now]) : now = now ?? DateTime.now;

  final DateTime Function() now;
  DateTime? serverExpiresAt;

  /// Se impostato, ogni riscatto risponde così (es. server giù).
  Either<Failure, Duration>? redeemResult;

  /// Se impostato, il riscatto aspetta che venga completato.
  Completer<void>? redeemGate;
  bool statusFails = false;
  int statusCalls = 0;
  int redeemCalls = 0;
  final List<StorePurchase> redeemed = [];

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
  Future<Either<Failure, Duration>> redeemPurchase(
    StorePurchase purchase,
  ) async {
    redeemCalls++;
    await redeemGate?.future;
    final forced = redeemResult;
    if (forced != null) return forced;
    if (!redeemed.contains(purchase)) {
      redeemed.add(purchase);
      serverExpiresAt = now().add(const Duration(hours: 2));
    }
    return Right(_remaining);
  }
}

/// Il negozio simulato vero, senza attese (o con [sheetDelay]).
StoreBillingDataSourceFakeImpl fakeStore({
  FakeStoreOutcome outcome = FakeStoreOutcome.success,
  Duration sheetDelay = Duration.zero,
  Duration approvalDelay = const Duration(seconds: 8),
  Iterable<StorePurchase> unfinishedAtStartup = const [],
}) => StoreBillingDataSourceFakeImpl(
  outcome: outcome,
  sheetDelay: sheetDelay,
  approvalDelay: approvalDelay,
  unfinishedAtStartup: unfinishedAtStartup,
);

/// `ProPaywall` montato come in `app.dart`, col negozio [store] (di default
/// quello simulato, con 800 ms di "finestra del negozio").
ProPaywall buildProPaywall({
  required SessionRepository sessions,
  required PaywallRepository paywall,
  StoreBillingDataSource? store,
  DateTime Function()? now,
}) {
  final storeRepository = StoreRepositoryImpl(
    store ?? fakeStore(sheetDelay: const Duration(milliseconds: 800)),
  );
  final resolve = ResolveUnlockExpiryUseCase(now: now);
  final redeem = RedeemStorePurchaseUseCase(
    paywallRepository: paywall,
    storeRepository: storeRepository,
    resolveUnlockExpiryUseCase: resolve,
  );
  return ProPaywall(
    watchSessionUseCase: WatchSessionUseCase(sessions),
    getUnlockStatusUseCase: GetUnlockStatusUseCase(
      paywall,
      resolveUnlockExpiryUseCase: resolve,
    ),
    purchaseUnlockUseCase: PurchaseUnlockUseCase(
      storeRepository: storeRepository,
      redeemStorePurchaseUseCase: redeem,
    ),
    getUnlockOfferUseCase: GetUnlockOfferUseCase(storeRepository),
    watchUnfinishedPurchasesUseCase: WatchUnfinishedPurchasesUseCase(
      storeRepository: storeRepository,
      redeemStorePurchaseUseCase: redeem,
    ),
    retryUnfinishedPurchasesUseCase: RetryUnfinishedPurchasesUseCase(
      storeRepository: storeRepository,
      redeemStorePurchaseUseCase: redeem,
    ),
    getUnlockTimeLeftUseCase: GetUnlockTimeLeftUseCase(now: now),
  );
}
