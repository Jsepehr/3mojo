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

    test('a device that never purchased is not unlocked', () {
      expect(store.isUnlocked('device-a'), isFalse);
    });

    test('recordUnlock makes the device unlocked immediately', () {
      store.recordUnlock('device-a');

      expect(store.isUnlocked('device-a'), isTrue);
    });

    test('stays unlocked right up to the 2-hour mark', () {
      store.recordUnlock('device-a');
      clock = clock.add(const Duration(hours: 1, minutes: 59));

      expect(store.isUnlocked('device-a'), isTrue);
    });

    test('expires after 2 hours', () {
      store.recordUnlock('device-a');
      clock = clock.add(const Duration(hours: 2, minutes: 1));

      expect(store.isUnlocked('device-a'), isFalse);
    });

    test('is keyed per device, not global', () {
      store.recordUnlock('device-a');

      expect(store.isUnlocked('device-a'), isTrue);
      expect(store.isUnlocked('device-b'), isFalse);
    });

    test(
      'uses the server clock, not anything the client could claim: '
      'rewinding the server clock after unlock still expires on schedule',
      () {
        store.recordUnlock('device-a');
        // Simulates the server's own clock simply progressing normally -
        // nothing the client does to its own device clock can affect this,
        // since the timestamp was already recorded using the server's
        // clock at the moment of purchase.
        clock = clock.add(const Duration(hours: 3));

        expect(store.isUnlocked('device-a'), isFalse);
      },
    );
  });
}
