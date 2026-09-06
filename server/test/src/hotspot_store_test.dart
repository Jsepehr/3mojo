import 'package:test/test.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/session_store.dart';

void main() {
  group('HotspotStore', () {
    late DateTime clock;
    late SessionStore sessions;
    late HotspotStore hotspots;

    setUp(() {
      clock = DateTime(2026, 1, 1);
      sessions = SessionStore.withClock(() => clock);
      hotspots = HotspotStore.withClock(() => clock);
    });

    void placeTrio() {
      // ~10m apart from each other — well within the 100m cluster radius.
      sessions.upsertPosition(sessionId: 'a', lat: 0.0000, lng: 0.0000);
      sessions.upsertPosition(sessionId: 'b', lat: 0.0001, lng: 0.0000);
      sessions.upsertPosition(sessionId: 'c', lat: 0.0000, lng: 0.0001);
    }

    test('does not form with only 2 mutually close sessions', () {
      sessions.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      sessions.upsertPosition(sessionId: 'b', lat: 0.0001, lng: 0);
      clock = clock.add(const Duration(minutes: 16));

      hotspots.detectAndRefresh(sessions.allSessions);

      expect(hotspots.active, isEmpty);
    });

    test('does not form before the minimum dwell threshold', () {
      placeTrio();
      clock = clock.add(const Duration(minutes: 14));

      hotspots.detectAndRefresh(sessions.allSessions);

      expect(hotspots.active, isEmpty);
    });

    test('forms at the centroid once 3+ are mutually close and stationary', () {
      placeTrio();
      clock = clock.add(const Duration(minutes: 15));

      hotspots.detectAndRefresh(sessions.allSessions);

      final hotspot = hotspots.active.single;
      expect(hotspot.centerLat, closeTo(0.0000333, 0.0000001));
      expect(hotspot.centerLng, closeTo(0.0000333, 0.0000001));
    });

    test('a "star" pattern does not qualify -- every pair must be close, '
        'not just each to one common member', () {
      // b and c are each close to a, but ~2.2km apart from each other.
      sessions.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      sessions.upsertPosition(sessionId: 'b', lat: 0.0001, lng: 0);
      sessions.upsertPosition(sessionId: 'c', lat: -0.01, lng: 0);
      clock = clock.add(const Duration(minutes: 16));

      hotspots.detectAndRefresh(sessions.allSessions);

      expect(hotspots.active, isEmpty);
    });

    test('detection ignores gender -- it is a physical fact, not a dating '
        'preference', () {
      sessions.upsertPosition(sessionId: 'a', lat: 0, lng: 0, gender: 'male');
      sessions.upsertPosition(
        sessionId: 'b',
        lat: 0.0001,
        lng: 0,
        gender: 'female',
      );
      sessions.upsertPosition(
        sessionId: 'c',
        lat: 0,
        lng: 0.0001,
        gender: 'female',
        genderPreference: 'male',
      );
      clock = clock.add(const Duration(minutes: 16));

      hotspots.detectAndRefresh(sessions.allSessions);

      expect(hotspots.active, hasLength(1));
    });

    test('renews at the same center while an equally tight group remains', () {
      placeTrio();
      clock = clock.add(const Duration(minutes: 16));
      hotspots.detectAndRefresh(sessions.allSessions);
      final formedLat = hotspots.active.single.centerLat;
      final formedLng = hotspots.active.single.centerLng;

      clock = clock.add(const Duration(hours: 1, minutes: 1));
      hotspots.detectAndRefresh(sessions.allSessions);

      final renewed = hotspots.active.single;
      expect(renewed.centerLat, formedLat);
      expect(renewed.centerLng, formedLng);
    });

    test('scattered strangers within the old radius do not keep it alive -- '
        'renewal requires the same mutual-closeness as formation', () {
      placeTrio();
      clock = clock.add(const Duration(minutes: 16));
      hotspots.detectAndRefresh(sessions.allSessions);

      // The founding trio leaves; three unrelated people each show up
      // within 200m of the OLD center, but ~350m apart from each other.
      // Scattered far apart from each other too, so they don't
      // incidentally form a brand-new hotspot of their own at their new
      // location -- that would mask what this test actually checks.
      sessions.upsertPosition(sessionId: 'a', lat: 5, lng: 5);
      sessions.upsertPosition(sessionId: 'b', lat: 6, lng: 6);
      sessions.upsertPosition(sessionId: 'c', lat: 7, lng: 7);
      sessions.upsertPosition(sessionId: 'x', lat: 0.0016, lng: 0);
      sessions.upsertPosition(sessionId: 'y', lat: -0.0016, lng: 0);
      sessions.upsertPosition(sessionId: 'z', lat: 0, lng: 0.0016);
      // Past both their own 15-min eligibility and the original 1h expiry.
      clock = clock.add(const Duration(hours: 1, minutes: 1));

      hotspots.detectAndRefresh(sessions.allSessions);

      expect(hotspots.active, isEmpty);
    });

    test(
      'recenters when the bare minimum remains and has drifted to the edge',
      () {
        placeTrio();
        clock = clock.add(const Duration(minutes: 16));
        hotspots.detectAndRefresh(sessions.allSessions);
        final originalLat = hotspots.active.single.centerLat;

        // Same trio walks ~150m away together, still mutually close, still
        // within the 200m circle around the old center -- but past its
        // core (100m), not near it.
        const shiftDeg = 0.00135;
        sessions.upsertPosition(sessionId: 'a', lat: shiftDeg, lng: 0);
        sessions.upsertPosition(sessionId: 'b', lat: shiftDeg + 0.0001, lng: 0);
        sessions.upsertPosition(sessionId: 'c', lat: shiftDeg, lng: 0.0001);
        clock = clock.add(const Duration(minutes: 16));

        hotspots.detectAndRefresh(sessions.allSessions);

        final recentered = hotspots.active.single;
        expect(recentered.centerLat, isNot(originalLat));
        expect(recentered.centerLat, closeTo(shiftDeg + 0.0000333, 0.0000001));
      },
    );

    test('does not recenter while more than the bare minimum remains near '
        'the core', () {
      placeTrio();
      sessions.upsertPosition(sessionId: 'd', lat: 0.00005, lng: 0.00005);
      clock = clock.add(const Duration(minutes: 16));
      hotspots.detectAndRefresh(sessions.allSessions);
      final originalLat = hotspots.active.single.centerLat;
      final originalLng = hotspots.active.single.centerLng;

      clock = clock.add(const Duration(hours: 1, minutes: 1));
      hotspots.detectAndRefresh(sessions.allSessions);

      final renewed = hotspots.active.single;
      expect(renewed.centerLat, originalLat);
      expect(renewed.centerLng, originalLng);
    });

    test('expires and is removed once nobody sustains it anymore', () {
      placeTrio();
      clock = clock.add(const Duration(minutes: 16));
      hotspots.detectAndRefresh(sessions.allSessions);
      expect(hotspots.active, hasLength(1));

      // Scattered far apart from each other too, so they don't incidentally
      // form a brand-new hotspot of their own at their new location.
      sessions.upsertPosition(sessionId: 'a', lat: 5, lng: 5);
      sessions.upsertPosition(sessionId: 'b', lat: 6, lng: 6);
      sessions.upsertPosition(sessionId: 'c', lat: 7, lng: 7);
      clock = clock.add(const Duration(hours: 1, minutes: 1));

      hotspots.detectAndRefresh(sessions.allSessions);

      expect(hotspots.active, isEmpty);
    });

    test('multiple hotspots can be active at once, in different areas', () {
      placeTrio();
      sessions.upsertPosition(sessionId: 'p', lat: 1, lng: 1);
      sessions.upsertPosition(sessionId: 'q', lat: 1.0001, lng: 1);
      sessions.upsertPosition(sessionId: 'r', lat: 1, lng: 1.0001);
      clock = clock.add(const Duration(minutes: 16));

      hotspots.detectAndRefresh(sessions.allSessions);

      expect(hotspots.active, hasLength(2));
    });

    test('sharesAnyActiveHotspot requires the SAME hotspot to cover both '
        'positions -- being in two different hotspots does not count', () {
      placeTrio();
      sessions.upsertPosition(sessionId: 'p', lat: 1, lng: 1);
      sessions.upsertPosition(sessionId: 'q', lat: 1.0001, lng: 1);
      sessions.upsertPosition(sessionId: 'r', lat: 1, lng: 1.0001);
      clock = clock.add(const Duration(minutes: 16));
      hotspots.detectAndRefresh(sessions.allSessions);

      expect(hotspots.sharesAnyActiveHotspot(0, 0, 1, 1), isFalse);
    });

    test('two genuinely separate clusters only ~250m apart do not both '
        'become hotspots -- their circles would overlap', () {
      placeTrio();
      // ~250m away: two independent triangles, but close enough that two
      // 200m-radius circles centered on each would overlap.
      const gapDeg = 0.00225;
      sessions.upsertPosition(sessionId: 'x', lat: gapDeg, lng: 0);
      sessions.upsertPosition(sessionId: 'y', lat: gapDeg + 0.0001, lng: 0);
      sessions.upsertPosition(sessionId: 'z', lat: gapDeg, lng: 0.0001);
      clock = clock.add(const Duration(minutes: 16));

      hotspots.detectAndRefresh(sessions.allSessions);

      expect(hotspots.active, hasLength(1));
    });

    test('refuses to recenter into overlap with another active hotspot', () {
      placeTrio();
      clock = clock.add(const Duration(minutes: 16));
      hotspots.detectAndRefresh(sessions.allSessions);
      final originalLat = hotspots.active.single.centerLat;

      // A second hotspot forms ~456m away -- far enough not to overlap the
      // first at formation time (needs >=400m).
      const bOffset = 0.0041;
      sessions.upsertPosition(sessionId: 'p', lat: bOffset, lng: 0);
      sessions.upsertPosition(sessionId: 'q', lat: bOffset + 0.0001, lng: 0);
      sessions.upsertPosition(sessionId: 'r', lat: bOffset, lng: 0.0001);
      clock = clock.add(const Duration(minutes: 16));
      hotspots.detectAndRefresh(sessions.allSessions);
      expect(hotspots.active, hasLength(2));

      // The first trio shrinks to the bare minimum and drifts ~180m toward
      // the second hotspot -- still within the first hotspot's 200m reach
      // (so it stays a "supporter"), but recentering onto this new centroid
      // would land only ~276m from the second hotspot: inside overlap range.
      const towardOther = 0.001617;
      sessions.upsertPosition(sessionId: 'a', lat: towardOther, lng: 0);
      sessions.upsertPosition(
        sessionId: 'b',
        lat: towardOther + 0.0001,
        lng: 0,
      );
      sessions.upsertPosition(sessionId: 'c', lat: towardOther, lng: 0.0001);
      clock = clock.add(const Duration(minutes: 16));

      hotspots.detectAndRefresh(sessions.allSessions);

      expect(hotspots.active, hasLength(2));
      final first = hotspots.active.firstWhere((h) => h.centerLat < 0.003);
      expect(first.centerLat, originalLat);
    });
  });
}
