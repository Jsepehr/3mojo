import 'package:test/test.dart';
import 'package:threemojo_server/src/paywall_store.dart';

void main() {
  group('PaywallStore', () {
    late DateTime clock;
    late PaywallStore store;

    setUp(() {
      clock = DateTime(2026, 1, 1);
      store = PaywallStore.withClock(() => clock);
    });

    test('an unknown or empty token is not unlocked', () {
      expect(store.isUnlocked('made-up'), isFalse);
      expect(store.isUnlocked(''), isFalse);
    });

    test('a freshly issued token is unlocked immediately', () {
      final token = store.issueUnlockToken();

      expect(store.isUnlocked(token), isTrue);
    });

    test('tokens are random and unique per purchase', () {
      final first = store.issueUnlockToken();
      final second = store.issueUnlockToken();

      expect(first, isNot(second));
      expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('stays unlocked right up to the 2-hour mark', () {
      final token = store.issueUnlockToken();
      clock = clock.add(const Duration(hours: 1, minutes: 59));

      expect(store.isUnlocked(token), isTrue);
    });

    test('expires after 2 hours', () {
      final token = store.issueUnlockToken();
      clock = clock.add(const Duration(hours: 2, minutes: 1));

      expect(store.isUnlocked(token), isFalse);
    });

    test('each token is independent: one purchase unlocks only its token', () {
      final token = store.issueUnlockToken();

      expect(store.isUnlocked(token), isTrue);
      expect(store.isUnlocked('${token}0'), isFalse);
    });

    test('uses the server clock, not anything the client could claim: '
        'the token expires on the server schedule', () {
      final token = store.issueUnlockToken();
      // Simulates the server's own clock simply progressing normally -
      // nothing the client does to its own device clock can affect this,
      // since the timestamp was recorded using the server's clock at the
      // moment of purchase.
      clock = clock.add(const Duration(hours: 3));

      expect(store.isUnlocked(token), isFalse);
    });

    group('remainingFor', () {
      test('is the full duration right after the purchase', () {
        final token = store.issueUnlockToken();

        expect(store.remainingFor(token), PaywallStore.unlockDuration);
        expect(store.remainingSecondsFor(token), 7200);
      });

      test('counts down on the server clock', () {
        final token = store.issueUnlockToken();
        clock = clock.add(const Duration(minutes: 18, milliseconds: 400));

        expect(
          store.remainingFor(token),
          const Duration(hours: 1, minutes: 41, seconds: 59, milliseconds: 600),
        );
        // Per difetto: mai un secondo in più di quanto resta davvero.
        expect(store.remainingSecondsFor(token), 6119);
      });

      test('is null (and 0 seconds) for unknown or expired tokens', () {
        final token = store.issueUnlockToken();
        expect(store.remainingFor('made-up'), isNull);
        expect(store.remainingSecondsFor('made-up'), 0);

        clock = clock.add(PaywallStore.unlockDuration);

        expect(store.remainingFor(token), isNull);
        expect(store.remainingSecondsFor(token), 0);
        expect(store.isUnlocked(token), isFalse);
      });
    });
  });
}
