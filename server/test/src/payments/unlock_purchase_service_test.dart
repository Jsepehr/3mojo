import 'dart:async';

import 'package:test/test.dart';
import 'package:threemojo_server/src/payments/fake_receipt_verifier.dart';
import 'package:threemojo_server/src/payments/payments.dart';
import 'package:threemojo_server/src/payments/payments_config.dart';
import 'package:threemojo_server/src/payments/receipt_verifier.dart';
import 'package:threemojo_server/src/payments/redeemed_transactions.dart';
import 'package:threemojo_server/src/payments/unlock_purchase_service.dart';
import 'package:threemojo_server/src/paywall_store.dart';

Matcher _rejected(ReceiptRejection reason) => throwsA(
  isA<ReceiptRejectedException>().having((e) => e.reason, 'reason', reason),
);

/// Un negozio controllabile: dice cosa ha "verificato" e se il consumo
/// riesce.
class _StubVerifier implements ReceiptVerifier {
  _StubVerifier(this.platform);

  @override
  final StorePlatform platform;
  String productId = 'raen.unlock_2h';
  DateTime purchasedAt = DateTime.utc(2026, 10, 23, 12);
  bool alreadyConsumed = false;
  bool storeEnforcesSingleUse = false;
  Object? finalizeError;
  Completer<void>? verifyGate;
  int verifyCalls = 0;
  int finalizeCalls = 0;

  @override
  Future<VerifiedPurchase> verify(PurchaseClaim claim) async {
    verifyCalls++;
    await verifyGate?.future;
    return VerifiedPurchase(
      platform: platform,
      transactionKey: claim.transactionId,
      productId: productId,
      purchasedAt: purchasedAt,
      alreadyConsumed: alreadyConsumed,
      storeEnforcesSingleUse: storeEnforcesSingleUse,
    );
  }

  @override
  Future<void> finalize(VerifiedPurchase purchase) async {
    finalizeCalls++;
    final error = finalizeError;
    if (error != null) throw error;
  }
}

PurchaseClaim _claim(
  String transactionId, {
  StorePlatform platform = StorePlatform.ios,
  String productId = 'raen.unlock_2h',
  String? receipt,
}) => PurchaseClaim(
  platform: platform,
  productId: productId,
  receipt: receipt ?? 'receipt-$transactionId',
  transactionId: transactionId,
);

void main() {
  late DateTime clock;
  late PaywallStore paywall;
  late RedeemedTransactions registry;
  late _StubVerifier apple;
  late _StubVerifier google;
  late UnlockPurchaseService service;

  setUp(() {
    clock = DateTime.utc(2026, 10, 23, 12, 30);
    paywall = PaywallStore.withClock(() => clock);
    registry = RedeemedTransactions(now: () => clock);
    apple = _StubVerifier(StorePlatform.ios);
    google = _StubVerifier(StorePlatform.android)
      ..storeEnforcesSingleUse = true;
    service = UnlockPurchaseService(
      verifiers: {StorePlatform.ios: apple, StorePlatform.android: google},
      productIds: {
        StorePlatform.ios: 'raen.unlock_2h',
        StorePlatform.android: 'raen.unlock_2h',
      },
      registry: registry,
      paywallStore: paywall,
      now: () => clock,
    );
  });

  test('a verified purchase unlocks for 2 hours on the server clock', () async {
    final grant = await service.redeem(_claim('t1'));

    expect(grant.replayed, isFalse);
    expect(grant.remaining, PaywallStore.unlockDuration);
    expect(paywall.isUnlocked(grant.unlockToken), isTrue);
  });

  test('the same transaction never unlocks twice: a retry gets the same '
      'token while it is valid, then 409', () async {
    final first = await service.redeem(_claim('t1'));
    clock = clock.add(const Duration(minutes: 30));

    final retry = await service.redeem(_claim('t1', receipt: 'other-copy'));
    expect(retry.replayed, isTrue);
    expect(retry.unlockToken, first.unlockToken);
    expect(retry.remaining, const Duration(minutes: 90));

    clock = clock.add(const Duration(hours: 2));
    await expectLater(
      service.redeem(_claim('t1')),
      throwsA(isA<PurchaseAlreadyRedeemedException>()),
    );
  });

  test(
    'two requests at the same time for one transaction get one token',
    () async {
      apple.verifyGate = Completer<void>();
      final a = service.redeem(_claim('t1', receipt: 'copy-a'));
      final b = service.redeem(_claim('t1', receipt: 'copy-b'));
      final c = service.redeem(_claim('t1', receipt: 'copy-a'));
      apple.verifyGate!.complete();

      final grants = await Future.wait([a, b, c]);

      expect(grants.map((g) => g.unlockToken).toSet(), hasLength(1));
      expect(apple.finalizeCalls, 1);
      expect(apple.verifyCalls, 2); // copy-a una volta sola
    },
  );

  test('the product must be the configured one — both as claimed and as '
      'signed by the store', () async {
    await expectLater(
      service.redeem(_claim('t1', productId: 'raen.other')),
      _rejected(ReceiptRejection.wrongProduct),
    );
    expect(apple.verifyCalls, 0);

    apple.productId = 'raen.other';
    await expectLater(
      service.redeem(_claim('t2')),
      _rejected(ReceiptRejection.wrongProduct),
    );
  });

  test('a platform without verifier is not enabled (no token)', () async {
    await expectLater(
      service.redeem(_claim('t1', platform: StorePlatform.fake)),
      throwsA(isA<PlatformNotEnabledException>()),
    );
  });

  test('Apple: a transaction older than maxPurchaseAge is too old', () async {
    apple.purchasedAt = clock.subtract(const Duration(days: 8));

    await expectLater(
      service.redeem(_claim('t1')),
      _rejected(ReceiptRejection.tooOld),
    );
  });

  test('Google: the store enforces single use — old purchases are fine, an '
      'already consumed one not in the registry is already redeemed', () async {
    google.purchasedAt = clock.subtract(const Duration(days: 30));
    final grant = await service.redeem(
      _claim('g1', platform: StorePlatform.android),
    );
    expect(paywall.isUnlocked(grant.unlockToken), isTrue);
    expect(google.finalizeCalls, 1);

    google.alreadyConsumed = true;
    // Nel registro: lo stesso token (risposta persa dopo il consumo).
    final retry = await service.redeem(
      _claim('g1', platform: StorePlatform.android),
    );
    expect(retry.unlockToken, grant.unlockToken);
    // Non nel registro (es. server riavviato): non si riscatta di nuovo.
    await expectLater(
      service.redeem(_claim('g2', platform: StorePlatform.android)),
      throwsA(isA<PurchaseAlreadyRedeemedException>()),
    );
  });

  test('if the store cannot finalize (Google consume), the token is revoked '
      'and the purchase can be redeemed again later', () async {
    google.finalizeError = const StoreUnavailableException('down');

    await expectLater(
      service.redeem(_claim('g1', platform: StorePlatform.android)),
      throwsA(isA<StoreUnavailableException>()),
    );
    expect(registry.length, 0);

    google.finalizeError = null;
    final grant = await service.redeem(
      _claim('g1', platform: StorePlatform.android),
    );
    expect(grant.replayed, isFalse);
    expect(paywall.isUnlocked(grant.unlockToken), isTrue);
  });

  test('a refund revokes the unlock of that transaction, and a later '
      'redeem of a refunded transaction is refused', () async {
    final grant = await service.redeem(_claim('t1'));

    expect(await service.revokeTransaction(StorePlatform.ios, 't1'), isTrue);
    expect(paywall.isUnlocked(grant.unlockToken), isFalse);
    expect(await service.revokeTransaction(StorePlatform.ios, 't1'), isFalse);

    await service.revokeTransaction(StorePlatform.ios, 'never-redeemed');
    await expectLater(
      service.redeem(_claim('never-redeemed')),
      throwsA(isA<PurchaseAlreadyRedeemedException>()),
    );
  });

  group('RedeemedTransactions', () {
    test('keys are HMACs, never the transaction id, and differ per platform '
        'and per key', () async {
      final a = RedeemedTransactions(hashKey: List.filled(32, 1));
      final b = RedeemedTransactions(hashKey: List.filled(32, 2));

      final hash = await a.hash(StorePlatform.ios, '2000000123456789');

      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(hash, isNot(contains('2000000123456789')));
      expect(
        hash,
        isNot(await a.hash(StorePlatform.android, '2000000123456789')),
      );
      expect(hash, isNot(await b.hash(StorePlatform.ios, '2000000123456789')));
      expect(hash, await a.hash(StorePlatform.ios, '2000000123456789'));
    });

    test('entries leave the registry after the retention', () async {
      registry.record('h', 'token');
      clock = clock.add(registry.retention);

      expect(registry.lookup('h'), isNull);
    });
  });

  group('Payments in fake mode (the default)', () {
    test(
      'accepts a fake-store receipt, once, and refuses real platforms',
      () async {
        final payments = Payments.fromConfig(
          const PaymentsConfig(mode: PaymentsMode.fake),
          paywallStore: paywall,
        );
        final receipt = await FakeReceiptVerifier.buildReceipt(
          transactionId: 'fake-1',
          purchasedAt: DateTime.now(),
        );
        final claim = PurchaseClaim(
          platform: StorePlatform.fake,
          productId: FakeReceiptVerifier.productId,
          receipt: receipt,
          transactionId: 'fake-1',
        );

        final grant = await payments.service.redeem(claim);
        final again = await payments.service.redeem(claim);

        expect(again.unlockToken, grant.unlockToken);
        expect(again.replayed, isTrue);
        await expectLater(
          payments.service.redeem(
            PurchaseClaim(
              platform: StorePlatform.ios,
              productId: 'raen.unlock_2h',
              receipt: receipt,
              transactionId: 'fake-1',
            ),
          ),
          throwsA(isA<PlatformNotEnabledException>()),
        );
      },
    );
  });

  group('Payments in real mode without credentials', () {
    test('no platform is enabled, the fake one neither', () async {
      final config = PaymentsConfig.fromEnvironment({'PAYMENTS_MODE': 'real'});
      final payments = Payments.fromConfig(config, paywallStore: paywall);
      final fakeReceipt = await FakeReceiptVerifier.buildReceipt(
        transactionId: 'fake-1',
        purchasedAt: DateTime.now(),
      );

      for (final platform in StorePlatform.values) {
        await expectLater(
          payments.service.redeem(
            PurchaseClaim(
              platform: platform,
              productId: platform == StorePlatform.fake
                  ? FakeReceiptVerifier.productId
                  : 'raen.unlock_2h',
              receipt: fakeReceipt,
              transactionId: 'fake-1',
            ),
          ),
          throwsA(isA<PlatformNotEnabledException>()),
          reason: platform.name,
        );
      }
      expect(payments.appleNotifications, isNull);
      expect(payments.googleNotifications, isNull);
    });
  });
}
