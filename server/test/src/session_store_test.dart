import 'package:test/test.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/meeting_chance.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/session_store.dart';

void main() {
  group('SessionStore', () {
    late DateTime clock;
    late SessionStore store;

    setUp(() {
      clock = DateTime(2026, 1, 1);
      store = SessionStore.withClock(() => clock);
    });

    test('nearbyPeople returns null if sessionId never sent a position', () {
      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isNull);
    });

    test('a person is invisible before 1 minute of presence', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);

      clock = clock.add(const Duration(seconds: 59));

      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isEmpty);
    });

    test('a person already there before you arrive shows up immediately', () {
      // 'b' has been in place for 6 minutes before 'a' ever asks — this is
      // the scenario that motivated arrivedAt-based (not tick-based) dwell.
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 6));
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);

      final result = store.nearbyPeople(sessionId: 'a', radiusMeters: 100)!;
      expect(result.single.meetingChance, MeetingChance.high);
    });

    test('meeting chance rises with dwell time: low -> medium -> high', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);

      clock = clock.add(const Duration(minutes: 1));
      expect(
        store
            .nearbyPeople(sessionId: 'a', radiusMeters: 100)!
            .single
            .meetingChance,
        MeetingChance.low,
      );

      clock = clock.add(const Duration(minutes: 2));
      expect(
        store
            .nearbyPeople(sessionId: 'a', radiusMeters: 100)!
            .single
            .meetingChance,
        MeetingChance.medium,
      );

      clock = clock.add(const Duration(minutes: 2));
      expect(
        store
            .nearbyPeople(sessionId: 'a', radiusMeters: 100)!
            .single
            .meetingChance,
        MeetingChance.high,
      );
    });

    test('moving away for 2+ readings in a row resets the dwell time', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);

      clock = clock.add(const Duration(minutes: 5));
      expect(
        store
            .nearbyPeople(sessionId: 'a', radiusMeters: 100)!
            .single
            .meetingChance,
        MeetingChance.high,
      );

      // 'b' walks far enough away for two readings in a row (confirming a
      // real move, not GPS noise), then comes right back — dwell time
      // should restart from zero.
      store.upsertPosition(sessionId: 'b', lat: 0.01, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0.01, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);

      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isEmpty);
    });

    test('a single noisy reading far from the anchor is forgiven', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      // One isolated GPS jump, then back close to the anchor — should not
      // be treated as a real move, dwell keeps accumulating uninterrupted.
      store.upsertPosition(sessionId: 'b', lat: 0.01, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);

      expect(
        store
            .nearbyPeople(sessionId: 'a', radiusMeters: 100)!
            .single
            .meetingChance,
        MeetingChance.high,
      );
    });

    test('someone outside the radius is not returned', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      // Roughly 1.1km away — well outside a 100m radius.
      store.upsertPosition(sessionId: 'b', lat: 0.01, lng: 0);

      clock = clock.add(const Duration(minutes: 5));

      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isEmpty);
    });

    test('genderPreference filters out non-matching genders', () {
      store.upsertPosition(
        sessionId: 'a',
        lat: 0,
        lng: 0,
        genderPreference: 'female',
      );
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0, gender: 'male');
      clock = clock.add(const Duration(minutes: 5));

      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isEmpty);
    });

    test('genderPreference "everyone" shows every gender', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0, gender: 'male');
      clock = clock.add(const Duration(minutes: 5));

      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isNotEmpty);
    });

    test('nearbyPeople returns the selfie the other session sent', () {
      store.upsertPosition(
        sessionId: 'a',
        lat: 0,
        lng: 0,
      );
      store.upsertPosition(
        sessionId: 'b',
        lat: 0,
        lng: 0,
        selfieBase64: 'ZmFrZS1zZWxmaWU=',
      );
      clock = clock.add(const Duration(minutes: 5));

      final result = store.nearbyPeople(sessionId: 'a', radiusMeters: 100)!;
      expect(result.single.selfieBase64, 'ZmFrZS1zZWxmaWU=');
    });

    test('remove() makes a session disappear from everyone else\'s list', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isNotEmpty);

      store.remove('b');

      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isEmpty);
    });

    test('purgeStale removes sessions silent for longer than maxAge', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      clock = clock.add(const Duration(seconds: 30));
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);

      // 'a' hasn't sent an update in 91s (past a 90s maxAge), 'b' has (61s).
      clock = clock.add(const Duration(seconds: 61));

      final removed = store.purgeStale(const Duration(seconds: 90));

      expect(removed, ['a']);
      expect(store.nearbyPeople(sessionId: 'b', radiusMeters: 100), isEmpty);
    });

    test('purgeStale keeps sessions that updated within maxAge', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      clock = clock.add(const Duration(seconds: 60));

      expect(store.purgeStale(const Duration(seconds: 90)), isEmpty);
    });

    group('with an active hotspot', () {
      late HotspotStore hotspots;

      setUp(() {
        hotspots = HotspotStore.withClock(() => clock);
      });

      test('widens visibility beyond radiusMeters for two people it covers', () {
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
        store.upsertPosition(sessionId: 'b', lat: 0.0001, lng: 0);
        store.upsertPosition(sessionId: 'c', lat: 0, lng: 0.0001);
        clock = clock.add(const Duration(minutes: 16));
        hotspots.detectAndRefresh(store.allSessions);

        // ~150m from the trio's centroid: too far from 'a' individually
        // under the 100m radius, but within the hotspot's 200m reach.
        store.upsertPosition(sessionId: 'd', lat: 0.00003 + 0.00135, lng: 0.00003);
        clock = clock.add(const Duration(minutes: 2));

        final result = store.nearbyPeople(
          sessionId: 'a',
          radiusMeters: 100,
          hotspotStore: hotspots,
        )!;

        expect(result.map((p) => p.sessionId), contains('d'));
      });

      test('never widens visibility without an injected/active hotspot', () {
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
        store.upsertPosition(sessionId: 'b', lat: 0.0001, lng: 0);
        store.upsertPosition(sessionId: 'c', lat: 0, lng: 0.0001);
        store.upsertPosition(sessionId: 'd', lat: 0.00003 + 0.00135, lng: 0.00003);
        clock = clock.add(const Duration(minutes: 16));
        // No detectAndRefresh call: hotspots.active stays empty.

        final result = store.nearbyPeople(
          sessionId: 'a',
          radiusMeters: 100,
          hotspotStore: hotspots,
        )!;

        expect(result.map((p) => p.sessionId), isNot(contains('d')));
      });

      test('does not widen visibility for someone outside the hotspot too', () {
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
        store.upsertPosition(sessionId: 'b', lat: 0.0001, lng: 0);
        store.upsertPosition(sessionId: 'c', lat: 0, lng: 0.0001);
        clock = clock.add(const Duration(minutes: 16));
        hotspots.detectAndRefresh(store.allSessions);

        // Genuinely unrelated and far from both 'a' and the hotspot.
        store.upsertPosition(sessionId: 'e', lat: 5, lng: 5);
        clock = clock.add(const Duration(minutes: 2));

        final result = store.nearbyPeople(
          sessionId: 'a',
          radiusMeters: 100,
          hotspotStore: hotspots,
        )!;

        expect(result.map((p) => p.sessionId), isNot(contains('e')));
      });
    });

    group('paywall visibility', () {
      late PaywallStore paywall;

      setUp(() {
        paywall = PaywallStore.withClock(() => clock);
      });

      void placeViewerAndSix() {
        // 'a' is the viewer. Six others at clearly increasing distances
        // (~11m apart), each with a distinct selfie so the free/locked
        // split is unambiguous to check by content.
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0, deviceId: 'dev-a');
        for (var i = 1; i <= 6; i++) {
          store.upsertPosition(
            sessionId: 'p$i',
            lat: 0.0001 * i,
            lng: 0,
            selfieBase64: 'selfie-$i',
          );
        }
        clock = clock.add(const Duration(minutes: 5));
      }

      test(
        'a viewer with no linked device is treated as locked -- the '
        'closest two thirds arrive with no selfie',
        () {
          placeViewerAndSix();

          final result = store.nearbyPeople(
            sessionId: 'a',
            radiusMeters: 1000,
            paywallStore: paywall,
          )!;

          // 6 people: floor(6/3) = 2 free -- the two FARTHEST (p5, p6).
          final bySessionId = {for (final p in result) p.sessionId: p};
          expect(bySessionId['p5']!.selfieBase64, 'selfie-5');
          expect(bySessionId['p6']!.selfieBase64, 'selfie-6');
          for (final id in ['p1', 'p2', 'p3', 'p4']) {
            expect(bySessionId[id]!.selfieBase64, isEmpty);
          }
        },
      );

      test(
        'distance and meeting chance stay populated even when the selfie '
        'is withheld -- only the photo is paywalled, never those',
        () {
          placeViewerAndSix();

          final result = store.nearbyPeople(
            sessionId: 'a',
            radiusMeters: 1000,
            paywallStore: paywall,
          )!;

          final locked = result.firstWhere((p) => p.sessionId == 'p1');
          expect(locked.selfieBase64, isEmpty);
          expect(locked.distanceMeters, greaterThan(0));
          expect(locked.meetingChance, MeetingChance.high);
        },
      );

      test('an unlocked device sees every selfie, none withheld', () {
        placeViewerAndSix();
        paywall.recordUnlock('dev-a');

        final result = store.nearbyPeople(
          sessionId: 'a',
          radiusMeters: 1000,
          paywallStore: paywall,
        )!;

        for (final person in result) {
          expect(person.selfieBase64, isNotEmpty);
        }
      });

      test(
        'a linked device only unlocks once ITS OWN deviceId is unlocked -- '
        'unlocking a different device does nothing for this viewer',
        () {
          placeViewerAndSix();
          paywall.recordUnlock('someone-elses-device');

          final result = store.nearbyPeople(
            sessionId: 'a',
            radiusMeters: 1000,
            paywallStore: paywall,
          )!;

          expect(
            result.where((p) => p.selfieBase64.isEmpty),
            hasLength(4),
          );
        },
      );

      test('never blanks below the 2-free minimum, even on a short list', () {
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0, deviceId: 'dev-a');
        store.upsertPosition(
          sessionId: 'p1',
          lat: 0.0001,
          lng: 0,
          selfieBase64: 'selfie-1',
        );
        store.upsertPosition(
          sessionId: 'p2',
          lat: 0.0002,
          lng: 0,
          selfieBase64: 'selfie-2',
        );
        clock = clock.add(const Duration(minutes: 5));

        final result = store.nearbyPeople(
          sessionId: 'a',
          radiusMeters: 1000,
          paywallStore: paywall,
        )!;

        for (final person in result) {
          expect(person.selfieBase64, isNotEmpty);
        }
      });
    });
  });
}
