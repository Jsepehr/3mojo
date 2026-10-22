import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/paywall/data/datasources/paywall_local_data_source.dart';
import 'package:threemojo_app/features/paywall/data/datasources/paywall_remote_data_source.dart';
import 'package:threemojo_app/features/paywall/data/repositories/paywall_repository_impl.dart';

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
  int statusCalls = 0;

  @override
  Future<UnlockGrant> purchase() async =>
      (token: 'tok', remaining: const Duration(seconds: 7199));

  @override
  Future<Duration> getRemaining(String unlockToken) async {
    statusCalls++;
    return remaining;
  }
}

void main() {
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

  test('a purchase keeps the token for as long as the server says', () async {
    final local = _FakeLocal();
    final repo = PaywallRepositoryImpl(local, _FakeRemote());

    final result = await repo.purchaseUnlock();

    expect(result.getRight().toNullable(), const Duration(seconds: 7199));
    expect(local.token, 'tok');
    expect(local.savedFor, const Duration(seconds: 7199));
  });
}
