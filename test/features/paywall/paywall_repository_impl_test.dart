import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:threemojo_app/core/config/store_config.dart';
import 'package:threemojo_app/core/errors/exceptions.dart';
import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/paywall/data/datasources/paywall_local_data_source.dart';
import 'package:threemojo_app/features/paywall/data/datasources/paywall_remote_data_source.dart';
import 'package:threemojo_app/features/paywall/data/datasources/paywall_remote_data_source_fake_impl.dart';
import 'package:threemojo_app/features/paywall/data/datasources/paywall_remote_data_source_impl.dart';
import 'package:threemojo_app/features/paywall/data/datasources/store_billing_data_source_fake_impl.dart';
import 'package:threemojo_app/features/paywall/data/models/fake_store_receipt.dart';
import 'package:threemojo_app/features/paywall/data/models/store_purchase_model.dart';
import 'package:threemojo_app/features/paywall/data/repositories/paywall_repository_impl.dart';
import 'package:threemojo_app/features/paywall/domain/entities/store_purchase.dart';

class _FakeLocal implements PaywallLocalDataSource {
  String? token;
  Duration? savedFor;

  @override
  Future<String?> readUnlockToken() async => token;

  @override
  Future<void> saveUnlockToken(String token, Duration validFor) async {
    this.token = token;
    savedFor = validFor;
  }

  @override
  Future<void> clearUnlockToken() async => token = null;
}

class _FakeRemote implements PaywallRemoteDataSource {
  Duration remaining = Duration.zero;
  Exception? redeemError;
  int statusCalls = 0;
  StorePurchaseModel? lastRedeemed;

  @override
  Future<UnlockGrant> redeemPurchase(StorePurchaseModel purchase) async {
    lastRedeemed = purchase;
    final error = redeemError;
    if (error != null) throw error;
    return (token: 'tok', remaining: const Duration(seconds: 7199));
  }

  @override
  Future<Duration> getRemaining(String unlockToken) async {
    statusCalls++;
    return remaining;
  }
}

const _purchase = StorePurchase(
  platform: StorePlatform.appStore,
  productId: 'raen.unlock_2h',
  transactionId: '2000000123456789',
  verificationData: 'eyJ.jws.sig',
);

void main() {
  group('PaywallRepositoryImpl', () {
    test('without a token there is nothing to ask the server', () async {
      final remote = _FakeRemote();
      final repo = PaywallRepositoryImpl(_FakeLocal(), remote);

      final result = await repo.getUnlockTimeRemaining();

      expect(result.getRight().toNullable(), Duration.zero);
      expect(remote.statusCalls, 0);
    });

    test('passes on the server remaining time; when it is over the token is '
        'dropped', () async {
      final local = _FakeLocal()..token = 'tok';
      final remote = _FakeRemote()..remaining = const Duration(minutes: 42);
      final repo = PaywallRepositoryImpl(local, remote);

      expect(
        (await repo.getUnlockTimeRemaining()).getRight().toNullable(),
        const Duration(minutes: 42),
      );
      expect(local.token, 'tok');

      remote.remaining = Duration.zero;
      expect(
        (await repo.getUnlockTimeRemaining()).getRight().toNullable(),
        Duration.zero,
      );
      expect(local.token, isNull);
    });

    test(
      'a redeemed purchase keeps the token for as long as the server says',
      () async {
        final local = _FakeLocal();
        final remote = _FakeRemote();
        final repo = PaywallRepositoryImpl(local, remote);

        final result = await repo.redeemPurchase(_purchase);

        expect(result.getRight().toNullable(), const Duration(seconds: 7199));
        expect(local.token, 'tok');
        expect(local.savedFor, const Duration(seconds: 7199));
        expect(remote.lastRedeemed?.toJson(), {
          'platform': 'ios',
          'productId': 'raen.unlock_2h',
          'receipt': 'eyJ.jws.sig',
          'transactionId': '2000000123456789',
        });
      },
    );

    test('each server answer has its own typed failure, and no token is '
        'kept', () async {
      final cases = <Exception, Failure>{
        const PurchaseRejectedException('refunded'):
            const PurchaseNotVerifiedFailure('refunded'),
        const PurchaseAlreadyRedeemedException():
            const PurchaseAlreadyRedeemedFailure(),
        const ServerException('502'): const ConnectionFailure('502'),
      };
      for (final MapEntry(key: error, value: failure) in cases.entries) {
        final local = _FakeLocal();
        final repo = PaywallRepositoryImpl(
          local,
          _FakeRemote()..redeemError = error,
        );

        expect(await repo.redeemPurchase(_purchase), Left(failure));
        expect(local.token, isNull);
      }
    });
  });

  group('PaywallRemoteDataSourceImpl', () {
    PaywallRemoteDataSourceImpl remote(int status, Object body) =>
        PaywallRemoteDataSourceImpl(
          client: MockClient(
            (request) async => http.Response(jsonEncode(body), status),
          ),
        );
    final model = StorePurchaseModel.fromEntity(_purchase);

    test('200 is the grant with the server remaining time', () async {
      final grant = await remote(200, {
        'unlockToken': 'tok',
        'expiresInSeconds': 7200,
        'remainingSeconds': 7100,
        'alreadyRedeemed': false,
      }).redeemPurchase(model);

      expect(grant.token, 'tok');
      expect(grant.remaining, const Duration(seconds: 7100));
    });

    test('the receipt goes in the JSON body', () async {
      late Map<String, dynamic> sent;
      final source = PaywallRemoteDataSourceImpl(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.url.path, '/paywall/purchase');
          return http.Response(
            jsonEncode({'unlockToken': 't', 'remainingSeconds': 1}),
            200,
          );
        }),
      );

      await source.redeemPurchase(model);

      expect(sent['receipt'], 'eyJ.jws.sig');
      expect(sent['platform'], 'ios');
    });

    test('422 → rejected with the code, 409 → already redeemed, anything '
        'else → server error (retry)', () async {
      await expectLater(
        remote(422, {'code': 'wrongProduct'}).redeemPurchase(model),
        throwsA(
          isA<PurchaseRejectedException>().having(
            (e) => e.code,
            'code',
            'wrongProduct',
          ),
        ),
      );
      await expectLater(
        remote(409, {'code': 'alreadyRedeemed'}).redeemPurchase(model),
        throwsA(isA<PurchaseAlreadyRedeemedException>()),
      );
      for (final status in [400, 429, 502, 503]) {
        await expectLater(
          remote(status, {'code': 'x'}).redeemPurchase(model),
          throwsA(isA<ServerException>()),
          reason: '$status',
        );
      }
    });
  });

  group('PaywallRemoteDataSourceFakeImpl (fake mode)', () {
    test('redeems a simulated-store purchase once: the same one again gets '
        'the same token', () async {
      final remote = PaywallRemoteDataSourceFakeImpl();
      final purchase = StorePurchaseModel.fromEntity(
        StoreBillingDataSourceFakeImpl.newPurchase(),
      );

      final first = await remote.redeemPurchase(purchase);
      final again = await remote.redeemPurchase(purchase);

      expect(again.token, first.token);
      expect(
        await remote.getRemaining(first.token),
        greaterThan(Duration.zero),
      );
    });

    test(
      'anything that is not a simulated-store receipt is rejected',
      () async {
        final remote = PaywallRemoteDataSourceFakeImpl();
        final fake = StoreBillingDataSourceFakeImpl.newPurchase();

        for (final purchase in [
          StorePurchaseModel.fromEntity(_purchase),
          StorePurchaseModel(
            platform: StorePlatform.fake,
            productId: fake.productId,
            transactionId: fake.transactionId,
            verificationData: '${fake.verificationData}x',
          ),
        ]) {
          await expectLater(
            remote.redeemPurchase(purchase),
            throwsA(isA<PurchaseRejectedException>()),
          );
        }
      },
    );
  });

  group('FakeStoreReceipt', () {
    test('same format and key as the server (golden HMAC, see '
        'fake_receipt_verifier_test.dart)', () {
      expect(
        FakeStoreReceipt.sign('fake-store-v1.eyJhIjoxfQ'),
        'LLfo3GhM_V-1Nun58mbJcrTN2QrUdJqfWDWlYokf-VI',
      );
    });

    test('round-trips, and a tampered receipt does not decode', () {
      final receipt = FakeStoreReceipt(
        transactionId: 'fake-1',
        productId: StoreConfig.fakeUnlockProductId,
        purchasedAt: DateTime.utc(2026, 10, 23, 9),
      ).encode();

      final decoded = FakeStoreReceipt.decode(receipt);

      expect(receipt, startsWith('fake-store-v1.'));
      expect(decoded?.transactionId, 'fake-1');
      expect(decoded?.purchasedAt, DateTime.utc(2026, 10, 23, 9));
      expect(FakeStoreReceipt.decode('${receipt}x'), isNull);
      expect(FakeStoreReceipt.decode('eyJ.jws.sig'), isNull);
    });
  });
}
