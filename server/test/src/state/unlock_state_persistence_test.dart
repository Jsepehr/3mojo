import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:threemojo_server/src/log.dart';
import 'package:threemojo_server/src/payments/payments.dart';
import 'package:threemojo_server/src/payments/payments_config.dart';
import 'package:threemojo_server/src/payments/receipt_verifier.dart';
import 'package:threemojo_server/src/payments/redeemed_transactions.dart';
import 'package:threemojo_server/src/payments/unlock_purchase_service.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/secure_file.dart';
import 'package:threemojo_server/src/state/unlock_state_persistence.dart';
import 'package:threemojo_server/src/state/unlock_state_store.dart';

class _Verifier implements ReceiptVerifier {
  @override
  StorePlatform get platform => StorePlatform.ios;

  @override
  Future<VerifiedPurchase> verify(PurchaseClaim claim) async =>
      VerifiedPurchase(
        platform: platform,
        transactionKey: claim.transactionId,
        productId: 'raen.unlock_2h',
        purchasedAt: DateTime.utc(2026, 10, 23, 12),
        alreadyConsumed: false,
        storeEnforcesSingleUse: false,
      );

  @override
  Future<void> finalize(VerifiedPurchase purchase) async {}
}

PurchaseClaim _claim(String id) => PurchaseClaim(
  platform: StorePlatform.ios,
  productId: 'raen.unlock_2h',
  receipt: 'receipt-$id',
  transactionId: id,
);

/// Un "processo": store, registro, persistenza e servizio nuovi sulla
/// stessa cartella e con la stessa chiave — come dopo un riavvio.
class _Process {
  _Process(this.dir, this.clock, {List<int>? key})
    : paywall = PaywallStore.withClock(clock),
      registry = RedeemedTransactions(hashKey: List.filled(32, 7), now: clock) {
    persistence = UnlockStatePersistence(
      store: UnlockStateStore(directory: dir, key: key ?? List.filled(32, 7)),
      paywall: paywall,
      registry: registry,
    );
    service = UnlockPurchaseService(
      verifiers: {StorePlatform.ios: _Verifier()},
      productIds: {StorePlatform.ios: 'raen.unlock_2h'},
      registry: registry,
      paywallStore: paywall,
      now: clock,
      persist: persistence.flush,
    );
  }

  final Directory dir;
  final DateTime Function() clock;
  final PaywallStore paywall;
  final RedeemedTransactions registry;
  late final UnlockStatePersistence persistence;
  late final UnlockPurchaseService service;
}

void main() {
  late Directory dir;
  late DateTime now;
  DateTime clock() => now;

  setUp(() async {
    Log.sink = (_) {};
    dir = await Directory.systemTemp.createTemp('unlock_state_test');
    now = DateTime.utc(2026, 10, 23, 12, 30);
  });

  tearDown(() => dir.delete(recursive: true));

  test('after a restart the unlock is still valid and the transaction '
      'cannot be redeemed twice', () async {
    final first = _Process(dir, clock);
    final grant = await first.service.redeem(_claim('tx-1'));
    expect(first.paywall.isUnlocked(grant.unlockToken), isTrue);

    // Riavvio: un processo nuovo, stesso disco.
    now = now.add(const Duration(minutes: 30));
    final second = _Process(dir, clock);
    final restored = await second.persistence.restore();

    expect(restored.unlocks, 1);
    expect(restored.transactions, 1);
    expect(second.paywall.isUnlocked(grant.unlockToken), isTrue);
    expect(
      second.paywall.remainingFor(grant.unlockToken),
      const Duration(hours: 1, minutes: 30),
    );
    // Lo stesso acquisto non vale due volte, nemmeno dopo il riavvio.
    await expectLater(
      second.service.redeem(_claim('tx-1')),
      throwsA(isA<PurchaseAlreadyRedeemedException>()),
    );
    // Un acquisto nuovo funziona.
    final other = await second.service.redeem(_claim('tx-2'));
    expect(second.paywall.isUnlocked(other.unlockToken), isTrue);
  });

  test('a refund after a restart still revokes the unlock', () async {
    final first = _Process(dir, clock);
    final grant = await first.service.redeem(_claim('tx-1'));

    final second = _Process(dir, clock);
    await second.persistence.restore();
    final revoked = await second.service.revokeTransaction(
      StorePlatform.ios,
      'tx-1',
    );

    expect(revoked, isTrue);
    expect(second.paywall.isUnlocked(grant.unlockToken), isFalse);
  });

  test('the file holds only hashes: no token, no transaction id, nothing '
      'readable; and it is 600', () async {
    final process = _Process(dir, clock);
    final grant = await process.service.redeem(_claim('tx-secret-1'));

    final file = UnlockStateStore(directory: dir, key: List.filled(32, 7)).file;
    final raw = String.fromCharCodes(await file.readAsBytes());
    expect(raw, isNot(contains(grant.unlockToken)));
    expect(raw, isNot(contains('tx-secret-1')));
    expect(raw, isNot(contains('unlocks')));

    final snapshot = process.persistence.snapshot();
    expect(
      snapshot.unlocks.keys.single,
      PaywallStore.hashToken(grant.unlockToken),
    );
    expect(snapshot.unlocks.keys.single, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      snapshot.transactions.keys.single,
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );

    if (!Platform.isWindows) {
      expect(await permissionsOf(file.path), '600');
      expect(await permissionsOf(dir.path), '700');
    }
    expect(
      dir.listSync().map((e) => e.path),
      isNot(contains(endsWith('.tmp'))),
    );
  });

  test('expired entries are not restored: unlocks after 2 hours, '
      'transactions after 8 days', () async {
    final first = _Process(dir, clock);
    await first.service.redeem(_claim('tx-1'));

    now = now.add(const Duration(hours: 2, minutes: 1));
    var second = _Process(dir, clock);
    var restored = await second.persistence.restore();
    await second.persistence.flush();
    expect(restored.unlocks, 0);
    expect(restored.transactions, 1, reason: 'the transaction lives 8 days');

    now = now.add(const Duration(days: 8));
    second = _Process(dir, clock);
    restored = await second.persistence.restore();
    await second.persistence.flush();
    expect(restored.transactions, 0);
  });

  test('compact rewrites the file once things have expired, even on a '
      'quiet server', () async {
    final first = _Process(dir, clock);
    await first.persistence.restore();
    await first.service.redeem(_claim('tx-1'));
    expect(first.persistence.snapshot().unlocks, hasLength(1));

    now = now.add(const Duration(days: 9));
    await first.persistence.compact();

    final reread = await UnlockStateStore(
      directory: dir,
      key: List.filled(32, 7),
    ).load();
    expect(reread!.isEmpty, isTrue);
  });

  test('a file with another key (or garbage) does not stop the server and '
      'is overwritten', () async {
    final first = _Process(dir, clock);
    await first.service.redeem(_claim('tx-1'));

    final other = _Process(dir, clock, key: List.filled(32, 9));
    final restored = await other.persistence.restore();
    expect(restored.unlocks, 0);
    expect(restored.transactions, 0);

    await other.service.redeem(_claim('tx-9'));
    final reread = await UnlockStateStore(
      directory: dir,
      key: List.filled(32, 9),
    ).load();
    expect(reread!.transactions, hasLength(1));
  });

  test('a failing disk never fails the purchase', () async {
    // La "cartella" è un file: ogni scrittura fallisce.
    final blocker = File('${dir.path}/not-a-dir')..writeAsStringSync('x');
    final process = _Process(Directory(blocker.path), clock);

    final grant = await process.service.redeem(_claim('tx-1'));

    expect(process.paywall.isUnlocked(grant.unlockToken), isTrue);
    expect(process.persistence.saveFailures, greaterThan(0));
  });

  group('Payments wiring', () {
    test('persistence only with a fixed hash key and a data directory', () {
      final withKey = Payments.fromConfig(
        PaymentsConfig(
          mode: PaymentsMode.fake,
          transactionHashKey: Uint8List(32),
        ),
        paywallStore: PaywallStore.withClock(clock),
        dataDirectory: dir,
      );
      final withoutKey = Payments.fromConfig(
        const PaymentsConfig(mode: PaymentsMode.fake),
        paywallStore: PaywallStore.withClock(clock),
        dataDirectory: dir,
      );
      final withoutDir = Payments.fromConfig(
        PaymentsConfig(
          mode: PaymentsMode.fake,
          transactionHashKey: Uint8List(32),
        ),
        paywallStore: PaywallStore.withClock(clock),
      );

      expect(withKey.persistence, isNotNull);
      expect(withoutKey.persistence, isNull);
      expect(withoutDir.persistence, isNull);
    });
  });
}
