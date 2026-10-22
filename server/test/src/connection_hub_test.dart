import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/encounter_store.dart';
import 'package:threemojo_server/src/presence_profile.dart';
import 'package:threemojo_server/src/pseudonyms.dart';
import 'package:threemojo_server/src/session_store.dart';

void main() {
  group('ConnectionHub', () {
    late DateTime clock;
    late SessionStore store;
    late ConnectionHub hub;
    late Pseudonyms pseudonyms;

    setUp(() {
      pseudonyms = Pseudonyms();
      clock = DateTime(2026, 1, 1);
      store = SessionStore.withClock(() => clock);
      // Throttle effectively off for these tests -- they call
      // broadcastNearbyUpdates() once and expect an immediate push, or
      // drive multiple pushes through their own separate timer
      // (startHotspotDetection). The throttle itself gets its own group
      // below, with a real interval.
      hub = ConnectionHub.withStore(
        store,
        pseudonyms: pseudonyms,
        broadcastThrottleInterval: Duration.zero,
        // Same for the per-viewer window: it gets its own group below.
        nearbyPushMinInterval: Duration.zero,
      );
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
      final aSees = (aPayload['people'] as List).single as Map;
      // Never the internal id: a per-viewer pseudonym that only 'a' can
      // resolve back to 'b'.
      expect(aSees['personId'], isNot('b'));
      expect(
        pseudonyms.resolve(
          viewerId: 'a',
          pseudonym: aSees['personId'] as String,
        ),
        'b',
      );

      final bPayload =
          jsonDecode(bMessages.single as String) as Map<String, dynamic>;
      final bSees = (bPayload['people'] as List).single as Map;
      expect(
        pseudonyms.resolve(
          viewerId: 'b',
          pseudonym: bSees['personId'] as String,
        ),
        'a',
      );
    });

    test('the nearby payload never carries a distance', () async {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0.0003, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final aMessages = <dynamic>[];
      hub.register(
        'a',
        StreamController<dynamic>()..stream.listen(aMessages.add),
      );
      hub.broadcastNearbyUpdates();
      await Future<void>.delayed(Duration.zero);

      final person =
          ((jsonDecode(aMessages.single as String) as Map)['people'] as List)
                  .single
              as Map;
      expect(person.keys, isNot(contains('distanceMeters')));
      expect(person['locked'], isFalse);
    });

    test('an unchanged nearby list is not pushed again', () async {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final aMessages = <dynamic>[];
      hub.register(
        'a',
        StreamController<dynamic>()..stream.listen(aMessages.add),
      );
      hub.broadcastNearbyUpdates();
      await Future<void>.delayed(Duration.zero);
      // 'b' moves a few meters: no distance in the payload, nothing changed
      // for 'a'.
      store.upsertPosition(sessionId: 'b', lat: 0.00001, lng: 0);
      hub.broadcastNearbyUpdates();
      await Future<void>.delayed(Duration.zero);

      expect(aMessages, hasLength(1));
    });

    test('a failure computing one session does not stop the others', () async {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final aMessages = <dynamic>[];
      final brokenSink = StreamController<dynamic>()..stream.listen((_) {});
      await brokenSink.close(); // add() on a closed sink throws.
      hub
        ..register('broken', brokenSink)
        ..register(
          'a',
          StreamController<dynamic>()..stream.listen(aMessages.add),
        );
      store.upsertPosition(sessionId: 'broken', lat: 0, lng: 0);

      hub.broadcastNearbyUpdates();
      await Future<void>.delayed(Duration.zero);

      expect(aMessages, isNotEmpty);
    });

    test('encounter snapshots show what the other person shows on their '
        'profile, never what they look for', () async {
      final encounters = EncounterStore.empty();
      hub = ConnectionHub.withStore(
        store,
        encounterStore: encounters,
        broadcastThrottleInterval: Duration.zero,
      );
      store
        ..upsertPosition(
          sessionId: 'a',
          lat: 0,
          lng: 0,
          profile: const PresenceProfile(
            gender: 'female',
            lookingFor: {'male'},
            intent: 'chat',
            languages: ['it', 'en'],
            showGender: true,
          ),
        )
        ..upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      encounters.sendRequest(fromSessionId: 'a', toSessionId: 'b');

      final bMessages = <dynamic>[];
      hub
        ..register(
          'b',
          StreamController<dynamic>()..stream.listen(bMessages.add),
        )
        ..pushEncounterSnapshot('b');
      await Future<void>.delayed(Duration.zero);

      final payload =
          jsonDecode(bMessages.single as String) as Map<String, dynamic>;
      final incoming = (payload['incoming'] as List).single as Map;
      expect(incoming['otherIntent'], 'chat');
      expect(incoming['otherLanguages'], ['it', 'en']);
      expect(incoming['otherGender'], 'female');
      expect(incoming['otherPersonId'], isNot('a'));
      expect(jsonEncode(payload), isNot(contains('lookingFor')));
    });

    test('finished requests carry no selfie nor profile', () async {
      final encounters = EncounterStore.empty();
      hub = ConnectionHub.withStore(
        store,
        encounterStore: encounters,
        broadcastThrottleInterval: Duration.zero,
      );
      store
        ..upsertPosition(
          sessionId: 'a',
          lat: 0,
          lng: 0,
          selfieBase64: 'selfie-a',
          profile: const PresenceProfile(intent: 'chat'),
        )
        ..upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      final request = encounters.sendRequest(
        fromSessionId: 'a',
        toSessionId: 'b',
      );
      encounters.respondToRequest(
        requestId: request.id,
        accepted: false,
        bySessionId: 'b',
      );

      final bMessages = <dynamic>[];
      hub
        ..register(
          'b',
          StreamController<dynamic>()..stream.listen(bMessages.add),
        )
        ..pushEncounterSnapshot('b');
      await Future<void>.delayed(Duration.zero);

      final incoming =
          ((jsonDecode(bMessages.single as String) as Map)['incoming'] as List)
                  .single
              as Map;
      expect(incoming['status'], 'declined');
      expect(incoming.keys, isNot(contains('otherSelfieBase64')));
      expect(incoming.keys, isNot(contains('otherIntent')));
    });

    test('the selfie of a request travels once per socket: later snapshots '
        'omit it, a new socket gets it again', () async {
      final encounters = EncounterStore.empty();
      hub = ConnectionHub.withStore(
        store,
        encounterStore: encounters,
        broadcastThrottleInterval: Duration.zero,
      );
      store
        ..upsertPosition(
          sessionId: 'a',
          lat: 0,
          lng: 0,
          selfieBase64: 'selfie-a',
          profile: const PresenceProfile(intent: 'chat'),
        )
        ..upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      encounters.sendRequest(fromSessionId: 'a', toSessionId: 'b');

      Map<dynamic, dynamic> incomingOf(Object? raw) =>
          ((jsonDecode(raw! as String) as Map)['incoming'] as List).single
              as Map;

      final first = <dynamic>[];
      hub
        ..register('b', StreamController<dynamic>()..stream.listen(first.add))
        ..pushEncounterSnapshot('b')
        ..pushEncounterSnapshot('b');
      await Future<void>.delayed(Duration.zero);

      expect(incomingOf(first[0])['otherSelfieBase64'], 'selfie-a');
      final repeated = incomingOf(first[1]);
      expect(repeated.keys, isNot(contains('otherSelfieBase64')));
      // Il resto (stato, profilo visibile) c'è sempre.
      expect(repeated['status'], 'pending');
      expect(repeated['otherIntent'], 'chat');

      // Riconnessione: un socket nuovo riparte da zero.
      final second = <dynamic>[];
      hub
        ..register('b', StreamController<dynamic>()..stream.listen(second.add))
        ..pushEncounterSnapshot('b');
      await Future<void>.delayed(Duration.zero);

      expect(incomingOf(second.single)['otherSelfieBase64'], 'selfie-a');
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

    test('unregister with a stale sink keeps the newer connection', () async {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final oldSink = StreamController<dynamic>()..stream.listen((_) {});
      final newMessages = <dynamic>[];
      final newSink = StreamController<dynamic>()
        ..stream.listen(newMessages.add);
      hub
        ..register('a', oldSink)
        // Riconnessione: il nuovo socket sostituisce il vecchio...
        ..register('a', newSink);

      // ...e la chiusura in ritardo del vecchio non deve staccarlo.
      expect(hub.unregister('a', sink: oldSink), isFalse);

      hub.broadcastNearbyUpdates();
      await Future<void>.delayed(Duration.zero);

      expect(newMessages, isNotEmpty);
      expect(hub.unregister('a', sink: newSink), isTrue);
    });

    test(
      'relayChatMessage forwards to the recipient only, if connected',
      () async {
        final encounters = EncounterStore.empty();
        final request = encounters.sendRequest(
          fromSessionId: 'a',
          toSessionId: 'b',
        );
        encounters.respondToRequest(
          requestId: request.id,
          accepted: true,
          bySessionId: 'b',
        );
        hub = ConnectionHub.withStore(
          store,
          encounterStore: encounters,
          pseudonyms: pseudonyms,
          broadcastThrottleInterval: Duration.zero,
        );
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

        final delivered = hub.relayChatMessage(
          fromSessionId: 'a',
          toSessionId: 'b',
          text: 'ciao',
        );
        await Future<void>.delayed(Duration.zero);

        expect(delivered, isTrue);
        expect(aMessages, isEmpty);
        final payload =
            jsonDecode(bMessages.single as String) as Map<String, dynamic>;
        expect(payload['type'], 'chatMessage');
        expect(payload['text'], 'ciao');
        expect(
          pseudonyms.resolve(
            viewerId: 'b',
            pseudonym: payload['fromPersonId'] as String,
          ),
          'a',
        );
        // Server time, not a client-declared one.
        expect(DateTime.tryParse(payload['sentAt'] as String), isNotNull);
      },
    );

    test('relayChatMessage drops messages between sessions without an active '
        'match', () async {
      hub = ConnectionHub.withStore(
        store,
        encounterStore: EncounterStore.empty(),
        broadcastThrottleInterval: Duration.zero,
      );
      final bMessages = <dynamic>[];
      hub.register(
        'b',
        StreamController<dynamic>()..stream.listen(bMessages.add),
      );

      final delivered = hub.relayChatMessage(
        fromSessionId: 'stranger',
        toSessionId: 'b',
        text: 'ciao',
      );
      await Future<void>.delayed(Duration.zero);

      expect(delivered, isFalse);
      expect(bMessages, isEmpty);
    });

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
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(aMessages, hasLength(1));

      // Something changes for 'a' without any broadcast being asked for
      // (an unchanged list is never pushed twice): the timer alone must
      // pick it up.
      store.upsertPosition(sessionId: 'c', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));
      await Future<void>.delayed(const Duration(milliseconds: 60));

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
        ),
        returnsNormally,
      );
    });

    group('per-viewer window', () {
      late ConnectionHub windowedHub;
      const window = Duration(milliseconds: 80);

      setUp(() {
        // Global throttle off: only the per-viewer window is under test.
        windowedHub = ConnectionHub.withStore(
          store,
          broadcastThrottleInterval: Duration.zero,
          nearbyPushMinInterval: window,
        );
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
        store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
        clock = clock.add(const Duration(minutes: 5));
      });

      tearDown(() => windowedHub.stopHotspotDetection());

      List<Object?> peopleIn(Object? raw) =>
          (jsonDecode(raw! as String) as Map)['people'] as List;

      test('a viewer gets at most one changed list per window, and the '
          'latest state at the end of it', () async {
        final aMessages = <dynamic>[];
        windowedHub
          ..register(
            'a',
            StreamController<dynamic>()..stream.listen(aMessages.add),
          )
          ..broadcastNearbyUpdates();
        await Future<void>.delayed(Duration.zero);
        expect(aMessages, hasLength(1));

        // Every broadcast changes what 'a' would see ('b' drops and comes
        // back): inside the window none of them goes out.
        for (var i = 0; i < 10; i++) {
          store.setConnected('b', connected: i.isOdd);
          windowedHub.broadcastNearbyUpdates();
        }
        store.setConnected('b', connected: false);
        windowedHub.broadcastNearbyUpdates();
        await Future<void>.delayed(Duration.zero);
        expect(aMessages, hasLength(1));

        await Future<void>.delayed(window * 1.5);
        expect(aMessages, hasLength(2));
        expect(peopleIn(aMessages.last), isEmpty);
      });

      test('a list that is back to what was sent is not sent again at the '
          'end of the window', () async {
        final aMessages = <dynamic>[];
        windowedHub
          ..register(
            'a',
            StreamController<dynamic>()..stream.listen(aMessages.add),
          )
          ..broadcastNearbyUpdates();
        await Future<void>.delayed(Duration.zero);

        store.setConnected('b', connected: false);
        windowedHub.broadcastNearbyUpdates();
        store.setConnected('b', connected: true);
        await Future<void>.delayed(window * 1.5);

        expect(aMessages, hasLength(1));
      });

      test('reconnecting does not reopen the window early', () async {
        final first = <dynamic>[];
        windowedHub
          ..register('a', StreamController<dynamic>()..stream.listen(first.add))
          ..broadcastNearbyUpdates();
        await Future<void>.delayed(Duration.zero);
        expect(first, hasLength(1));

        final second = <dynamic>[];
        windowedHub
          ..register(
            'a',
            StreamController<dynamic>()..stream.listen(second.add),
          )
          ..broadcastNearbyUpdates();
        await Future<void>.delayed(Duration.zero);
        expect(second, isEmpty);

        await Future<void>.delayed(window * 1.5);
        expect(second, hasLength(1));
      });

      test('each viewer has its own window', () async {
        final aMessages = <dynamic>[];
        final bMessages = <dynamic>[];
        windowedHub
          ..register(
            'a',
            StreamController<dynamic>()..stream.listen(aMessages.add),
          )
          ..broadcastNearbyUpdates();
        await Future<void>.delayed(Duration.zero);

        // 'b' connects inside 'a''s window: its first list goes out now.
        windowedHub
          ..register(
            'b',
            StreamController<dynamic>()..stream.listen(bMessages.add),
          )
          ..broadcastNearbyUpdates();
        await Future<void>.delayed(Duration.zero);

        expect(aMessages, hasLength(1));
        expect(bMessages, hasLength(1));
      });
    });

    group('broadcast throttle', () {
      late ConnectionHub throttledHub;

      setUp(() {
        throttledHub = ConnectionHub.withStore(
          store,
          broadcastThrottleInterval: const Duration(milliseconds: 50),
          // Only the global throttle here; the per-viewer window has its
          // own group.
          nearbyPushMinInterval: Duration.zero,
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

        // 10 calls in quick succession, well inside the 50ms window, each
        // after a change for 'a' ('b' drops and comes back; an unchanged
        // list would never be pushed twice anyway). It ends dropped, so the
        // trailing push differs from the leading one.
        for (var i = 0; i < 10; i++) {
          store.setConnected('b', connected: i.isEven);
          throttledHub.broadcastNearbyUpdates();
        }
        store.setConnected('b', connected: false);
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

      test(
        'calls spaced apart, each past the window, are never coalesced',
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
          store.setConnected('b', connected: false);
          throttledHub.broadcastNearbyUpdates();
          await Future<void>.delayed(const Duration(milliseconds: 70));
          store.setConnected('b', connected: true);
          throttledHub.broadcastNearbyUpdates();
          await Future<void>.delayed(Duration.zero);

          expect(aMessages, hasLength(3));
        },
      );
    });
  });
}
