import 'dart:convert';

import 'package:test/test.dart';
import 'package:threemojo_server/src/payments/apple_jws_verifier.dart';
import 'package:threemojo_server/src/crypto/ecdsa.dart';
import 'package:threemojo_server/src/payments/payments_config.dart';
import 'package:threemojo_server/src/payments/receipt_verifier.dart';
import 'package:threemojo_server/src/payments/redeemed_transactions.dart';
import 'package:threemojo_server/src/payments/store_notifications.dart';
import 'package:threemojo_server/src/payments/unlock_purchase_service.dart';
import 'package:threemojo_server/src/paywall_store.dart';

import 'test_pki.dart';

/// Accetta tutto: qui conta solo cosa fanno le notifiche dopo il riscatto.
class _AcceptAll implements ReceiptVerifier {
  _AcceptAll(this.platform);

  @override
  final StorePlatform platform;

  @override
  Future<VerifiedPurchase> verify(PurchaseClaim claim) async =>
      VerifiedPurchase(
        platform: platform,
        transactionKey: claim.receipt,
        productId: claim.productId,
        purchasedAt: DateTime.now(),
      );

  @override
  Future<void> finalize(VerifiedPurchase purchase) async {}
}

void main() {
  late TestAppleChain chain;
  late PaywallStore paywall;
  late UnlockPurchaseService service;

  setUp(() {
    chain = TestAppleChain();
    paywall = PaywallStore.withClock(DateTime.now);
    service = UnlockPurchaseService(
      verifiers: {
        StorePlatform.ios: _AcceptAll(StorePlatform.ios),
        StorePlatform.android: _AcceptAll(StorePlatform.android),
      },
      productIds: {
        StorePlatform.ios: 'raen.unlock_2h',
        StorePlatform.android: 'raen.unlock_2h',
      },
      registry: RedeemedTransactions(),
      paywallStore: paywall,
    );
  });

  Future<String> redeem(StorePlatform platform, String key) async =>
      (await service.redeem(
        PurchaseClaim(
          platform: platform,
          productId: 'raen.unlock_2h',
          receipt: key,
          transactionId: '',
        ),
      )).unlockToken;

  group('AppleNotificationHandler', () {
    late AppleNotificationHandler handler;

    setUp(() {
      handler = AppleNotificationHandler(
        settings: AppleStoreSettings(
          bundleId: 'it.ameol.raen',
          productId: 'raen.unlock_2h',
          environment: AppleEnvironment.sandbox,
          trustedRoots: [chain.root],
        ),
        service: service,
        jwsVerifier: AppleJwsVerifier(trustedRoots: [chain.root]),
      );
    });

    Map<String, Object?> notification(String type, {String? transactionId}) => {
      'signedPayload': chain.signJws({
        'notificationType': type,
        'notificationUUID': 'uuid',
        'version': '2.0',
        'data': {
          'bundleId': 'it.ameol.raen',
          'environment': 'Sandbox',
          'signedTransactionInfo': chain.signJws(
            appleTransaction(
              transactionId: transactionId ?? '2000000123456789',
            ),
          ),
        },
      }),
    };

    test('REFUND revokes the unlock of that transaction', () async {
      final token = await redeem(StorePlatform.ios, '2000000123456789');

      expect(
        await handler.handle(notification('REFUND')),
        NotificationOutcome.revoked,
      );
      expect(paywall.isUnlocked(token), isFalse);
    });

    test('other notification types change nothing', () async {
      final token = await redeem(StorePlatform.ios, '2000000123456789');

      for (final type in ['CONSUMPTION_REQUEST', 'TEST', 'REFUND_DECLINED']) {
        expect(
          await handler.handle(notification(type)),
          NotificationOutcome.ignored,
        );
      }
      expect(paywall.isUnlocked(token), isTrue);
    });

    test('a notification not signed by the trusted chain is invalid', () async {
      final token = await redeem(StorePlatform.ios, '2000000123456789');
      final forged = TestAppleChain(
        rootKey: TestKey(EcCurve.p384, BigInt.from(777)),
      );

      expect(
        await handler.handle({
          'signedPayload': forged.signJws({
            'notificationType': 'REFUND',
            'data': {'bundleId': 'it.ameol.raen', 'environment': 'Sandbox'},
          }),
        }),
        NotificationOutcome.invalid,
      );
      expect(await handler.handle({'x': 1}), NotificationOutcome.invalid);
      expect(paywall.isUnlocked(token), isTrue);
    });
  });

  group('GoogleNotificationHandler', () {
    late GoogleNotificationHandler handler;

    setUp(() {
      handler = GoogleNotificationHandler(
        settings: const GooglePlaySettings(
          packageName: 'it.ameol.raen',
          productId: 'raen.unlock_2h',
          serviceAccountJson: '{}',
          rtdnToken: 'secret-secret-secret-secret-secret',
        ),
        service: service,
      );
    });

    Map<String, Object?> push(Map<String, Object?> data) => {
      'message': {
        'data': base64.encode(utf8.encode(jsonEncode(data))),
        'messageId': '1',
      },
      'subscription': 'projects/p/subscriptions/s',
    };

    test(
      'a voided purchase revokes the unlock of that purchase token',
      () async {
        final token = await redeem(StorePlatform.android, 'purchase-token-1');

        expect(
          await handler.handle(
            push({
              'packageName': 'it.ameol.raen',
              'voidedPurchaseNotification': {
                'purchaseToken': 'purchase-token-1',
                'orderId': 'GPA.1',
                'productType': 2,
                'refundType': 1,
              },
            }),
          ),
          NotificationOutcome.revoked,
        );
        expect(paywall.isUnlocked(token), isFalse);
      },
    );

    test('a test notification is fine, another package is invalid', () async {
      expect(
        await handler.handle(
          push({'packageName': 'it.ameol.raen', 'testNotification': {}}),
        ),
        NotificationOutcome.ignored,
      );
      expect(
        await handler.handle(
          push({
            'packageName': 'com.other',
            'voidedPurchaseNotification': {'purchaseToken': 'x'},
          }),
        ),
        NotificationOutcome.invalid,
      );
      expect(
        await handler.handle({
          'message': {'data': '%%%'},
        }),
        NotificationOutcome.invalid,
      );
    });
  });
}
