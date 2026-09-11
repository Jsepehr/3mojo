import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/session_store.dart';

void main() {
  group('ConnectionHub', () {
    late DateTime clock;
    late SessionStore store;
    late ConnectionHub hub;

    setUp(() {
      clock = DateTime(2026, 1, 1);
      store = SessionStore.withClock(() => clock);
      // Throttle effectively off for these tests -- they call
      // broadcastNearbyUpdates() once and expect an immediate push, or
      // drive multiple pushes through their own separate timer
      // (startHotspotDetection). The throttle itself gets its own group
      // below, with a real interval.
      hub = ConnectionHub.withStore(store, broadcastThrottleInterval: Duration.zero);
    });

    tearDown(() {
      // Harmless no-op if a test never started it -- avoids a dangling
      // Timer.periodic bleeding into the next test (same gotcha documented
      // for ProNearby/ProEncounters in the developer guide).
      hub.stopHotspotDetection();
    });

    test('broadcasts each registered session its own nearby list', () async {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final aMessages = <dynamic>[];
      final bMessages = <dynamic>[];
      hub.register(
        'a',
        StreamController<dynamic>()..stream.listen(aMessages.add),
      );
      hub.register(
        'b',
        StreamController<dynamic>()..stream.listen(bMessages.add),
      );

      hub.broadcastNearbyUpdates();
      await Future<void>.delayed(Duration.zero);

      final aPayload =
          jsonDecode(aMessages.single as String) as Map<String, dynamic>;
      expect(aPayload['type'], 'nearby');
      expect((aPayload['people'] as List).single['sessionId'], 'b');

      final bPayload =
          jsonDecode(bMessages.single as String) as Map<String, dynamic>;
      expect((bPayload['people'] as List).single['sessionId'], 'a');
    });

    test('unregister stops further pushes to that session', () async {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final aMessages = <dynamic>[];
      hub.register(
        'a',
        StreamController<dynamic>()..stream.listen(aMessages.add),
      );
      hub.unregister('a');

      hub.broadcastNearbyUpdates();
      await Future<void>.delayed(Duration.zero);

      expect(aMessages, isEmpty);
    });

    test(
      'relayChatMessage forwards to the recipient only, if connected',
      () async {
        final aMessages = <dynamic>[];
        final bMessages = <dynamic>[];
        hub.register(
          'a',
          StreamController<dynamic>()..stream.listen(aMessages.add),
        );
        hub.register(
          'b',
          StreamController<dynamic>()..stream.listen(bMessages.add),
        );

        hub.relayChatMessage(
          fromSessionId: 'a',
          toSessionId: 'b',
          text: 'ciao',
          sentAt: '2026-01-01T00:00:00.000Z',
        );
        await Future<void>.delayed(Duration.zero);

        expect(aMessages, isEmpty);
        final payload =
            jsonDecode(bMessages.single as String) as Map<String, dynamic>;
        expect(payload, {
          'type': 'chatMessage',
          'fromSessionId': 'a',
          'text': 'ciao',
          'sentAt': '2026-01-01T00:00:00.000Z',
        });
      },
    );

    test('startHotspotDetection pushes nearby updates on its own timer, '
        'without any presence message triggering it', () async {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final aMessages = <dynamic>[];
      hub.register(
        'a',
        StreamController<dynamic>()..stream.listen(aMessages.add),
      );

      hub.startHotspotDetection(interval: const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(aMessages.length, greaterThanOrEqualTo(2));
    });

    test('startHotspotDetection is idempotent -- a second call does not start '
        'a second timer', () async {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final aMessages = <dynamic>[];
      hub.register(
        'a',
        StreamController<dynamic>()..stream.listen(aMessages.add),
      );

      hub.startHotspotDetection(interval: const Duration(milliseconds: 30));
      hub.startHotspotDetection(interval: const Duration(milliseconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // A single 30ms timer fires ~3 times in 100ms; two independent
      // timers would roughly double that. Loose bound to avoid flakiness.
      expect(aMessages.length, lessThan(6));
    });

    test('relayChatMessage to a disconnected session is silently dropped', () {
      // No sink registered for 'ghost' — must not throw.
      expect(
        () => hub.relayChatMessage(
          fromSessionId: 'a',
          toSessionId: 'ghost',
          text: 'ciao',
          sentAt: '2026-01-01T00:00:00.000Z',
        ),
        returnsNormally,
      );
    });

    group('broadcast throttle', () {
      late ConnectionHub throttledHub;

      setUp(() {
        throttledHub = ConnectionHub.withStore(
          store,
          broadcastThrottleInterval: const Duration(milliseconds: 50),
        );
      });

      test('a single call still pushes immediately -- no delay with light '
          'traffic', () async {
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
        store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
        clock = clock.add(const Duration(minutes: 5));

        final aMessages = <dynamic>[];
        throttledHub.register(
          'a',
          StreamController<dynamic>()..stream.listen(aMessages.add),
        );

        throttledHub.broadcastNearbyUpdates();
        await Future<void>.delayed(Duration.zero);

        expect(aMessages, hasLength(1));
      });

      test('a burst of calls within the window collapses to the leading '
          'push plus exactly one trailing push', () async {
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
        store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
        clock = clock.add(const Duration(minutes: 5));

        final aMessages = <dynamic>[];
        throttledHub.register(
          'a',
          StreamController<dynamic>()..stream.listen(aMessages.add),
        );

        // 10 calls in quick succession, well inside the 50ms window.
        for (var i = 0; i < 10; i++) {
          throttledHub.broadcastNearbyUpdates();
        }
        await Future<void>.delayed(Duration.zero);
        expect(
          aMessages,
          hasLength(1),
          reason: 'only the leading call should have pushed so far',
        );

        // Past the window: the trailing push (because more calls came in
        // during it) should have fired exactly once more, not 9 more times.
        await Future<void>.delayed(const Duration(milliseconds: 70));
        expect(aMessages, hasLength(2));
      });

      test('calls spaced apart, each past the window, are never coalesced',
          () async {
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
        store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
        clock = clock.add(const Duration(minutes: 5));

        final aMessages = <dynamic>[];
        throttledHub.register(
          'a',
          StreamController<dynamic>()..stream.listen(aMessages.add),
        );

        throttledHub.broadcastNearbyUpdates();
        await Future<void>.delayed(const Duration(milliseconds: 70));
        throttledHub.broadcastNearbyUpdates();
        await Future<void>.delayed(const Duration(milliseconds: 70));
        throttledHub.broadcastNearbyUpdates();
        await Future<void>.delayed(Duration.zero);

        expect(aMessages, hasLength(3));
      });
    });
  });
}
