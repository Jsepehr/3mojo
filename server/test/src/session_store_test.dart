import 'package:test/test.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/meeting_chance.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/presence_profile.dart';
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

    test('a person already there before you arrive shows up as soon as you '
        'have stayed put for a minute yourself, with their own dwell', () {
      // 'b' has been in place for 6 minutes before 'a' ever asks — this is
      // the scenario that motivated arrivedAt-based (not tick-based) dwell.
      // It used to show up immediately: now the viewer must stay put too
      // (otherwise a fake GPS walking along the edge of the circle is a
      // location oracle), so 'a' sees nobody for its own first minute.
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 6));
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);

      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isEmpty);
      clock = clock.add(const Duration(seconds: 59));
      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isEmpty);

      clock = clock.add(const Duration(seconds: 1));
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

    test('moving away for 3 readings in a row resets the dwell time', () {
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

      // 'b' walks far enough away for three readings in a row (the median
      // of the last three readings leaves the anchor twice in a row:
      // a real move, not GPS noise), then comes right back — dwell time
      // should restart from zero. Readings 10 s apart: closer ones are
      // ignored by the per-session rate limit.
      for (final lat in [0.001, 0.001, 0.001, 0.0]) {
        clock = clock.add(SessionStore.minPositionInterval);
        store.upsertPosition(sessionId: 'b', lat: lat, lng: 0);
      }

      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isEmpty);
    });

    test('a single noisy reading far from the anchor is forgiven', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      // One isolated GPS jump, then back close to the anchor — should not
      // be treated as a real move, dwell keeps accumulating uninterrupted.
      for (final lat in [0.001, 0.0, 0.0]) {
        clock = clock.add(SessionStore.minPositionInterval);
        store.upsertPosition(sessionId: 'b', lat: lat, lng: 0);
      }

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

    test('finds someone within radius even across a latitude-band boundary '
        '(the spatial index must not miss a valid neighbor just because it '
        'straddles a band edge)', () {
      // ~89m apart -- within the 100m radius -- but on opposite sides of
      // the band edge at lat=0 (band width 100m): 'a' falls in band -1,
      // 'b' in band 0.
      store.upsertPosition(sessionId: 'a', lat: -0.0004, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0.0004, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final result = store.nearbyPeople(sessionId: 'a', radiusMeters: 100)!;

      expect(result.map((p) => p.sessionId), contains('b'));
    });

    group('reciprocal matching', () {
      bool sees(String viewer, String other) => store
          .nearbyPeople(sessionId: viewer, radiusMeters: 100)!
          .any((p) => p.sessionId == other);

      void place(String id, PresenceProfile profile) =>
          store.upsertPosition(sessionId: id, lat: 0, lng: 0, profile: profile);

      test('a man looking for women does NOT see a woman looking only for '
          'women, and she does not see him', () {
        place(
          'marco',
          const PresenceProfile(gender: 'male', lookingFor: {'female'}),
        );
        place(
          'giulia',
          const PresenceProfile(gender: 'female', lookingFor: {'female'}),
        );
        clock = clock.add(const Duration(minutes: 5));

        expect(sees('marco', 'giulia'), isFalse);
        expect(sees('giulia', 'marco'), isFalse);
      });

      test(
        'two people who each fit what the other looks for see each other',
        () {
          place(
            'a',
            const PresenceProfile(gender: 'male', lookingFor: {'female'}),
          );
          place(
            'b',
            const PresenceProfile(gender: 'female', lookingFor: {'male'}),
          );
          clock = clock.add(const Duration(minutes: 5));

          expect(sees('a', 'b'), isTrue);
          expect(sees('b', 'a'), isTrue);
        },
      );

      test('"prefer not to say" is visible only to people looking for '
          'everyone, and sees only people who accept everyone', () {
        place('anon', const PresenceProfile());
        place('open', const PresenceProfile(gender: 'female'));
        place(
          'picky',
          const PresenceProfile(gender: 'male', lookingFor: {'female'}),
        );
        clock = clock.add(const Duration(minutes: 5));

        expect(sees('open', 'anon'), isTrue);
        expect(sees('anon', 'open'), isTrue);
        expect(sees('picky', 'anon'), isFalse);
        expect(sees('anon', 'picky'), isFalse);
      });

      test('the profile is fixed at session start: a later presence cannot '
          'change the gender to probe someone else', () {
        place(
          'target',
          const PresenceProfile(gender: 'female', lookingFor: {'female'}),
        );
        place(
          'prober',
          const PresenceProfile(gender: 'male', lookingFor: {'female'}),
        );
        clock = clock.add(const Duration(minutes: 5));
        expect(sees('prober', 'target'), isFalse);

        // Same session claims to be a woman now: ignored.
        place(
          'prober',
          const PresenceProfile(gender: 'female', lookingFor: {'female'}),
        );

        expect(sees('prober', 'target'), isFalse);
      });
    });

    test('nearby results expose intent and languages, the gender only when '
        'shown, and never what the person looks for', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(
        sessionId: 'b',
        lat: 0,
        lng: 0,
        profile: const PresenceProfile(
          gender: 'nonBinary',
          intent: 'chat',
          languages: ['it', 'en'],
          showGender: true,
        ),
      );
      store.upsertPosition(
        sessionId: 'c',
        lat: 0,
        lng: 0,
        profile: const PresenceProfile(gender: 'female'),
      );
      clock = clock.add(const Duration(minutes: 5));

      final people = store.nearbyPeople(sessionId: 'a', radiusMeters: 100)!;
      final b = people
          .firstWhere((p) => p.sessionId == 'b')
          .toJson(personId: 'pseudo-b');
      final c = people
          .firstWhere((p) => p.sessionId == 'c')
          .toJson(personId: 'pseudo-c');

      expect(b['intent'], 'chat');
      expect(b['languages'], ['it', 'en']);
      expect(b['gender'], 'nonBinary');
      expect(c.containsKey('gender'), isFalse);
      for (final json in [b, c]) {
        expect(json.containsKey('lookingFor'), isFalse);
      }
    });

    test('nearbyPeople returns the selfie the other session sent', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
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

    test('a session in its grace period is invisible, then visible again '
        'with its dwell time intact', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      store.setConnected('b', connected: false);
      expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isEmpty);
      expect(store.isOnline('b'), isFalse);
      expect(store.allSessions.map((s) => s.sessionId), isNot(contains('b')));

      store.setConnected('b', connected: true);
      final result = store.nearbyPeople(sessionId: 'a', radiusMeters: 100)!;
      expect(result.single.meetingChance, MeetingChance.high);
    });

    test('rejects non-finite or out-of-range coordinates without breaking '
        'anything', () {
      for (final (lat, lng) in [
        (double.infinity, 0.0),
        (0.0, double.nan),
        (91.0, 0.0),
        (0.0, -181.0),
      ]) {
        expect(
          store.upsertPosition(sessionId: 'x', lat: lat, lng: lng),
          PresenceOutcome.invalidCoordinates,
        );
      }
      expect(store.contains('x'), isFalse);

      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      expect(
        () => store.nearbyPeople(sessionId: 'a', radiusMeters: 100),
        returnsNormally,
      );
    });

    test('a physically impossible jump is discarded, a plausible one is '
        'accepted once enough time has passed', () {
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      // Past the rate limit (a closer presence would just be ignored as
      // tooSoon, before any speed check).
      clock = clock.add(SessionStore.minPositionInterval);

      // ~11km in ten seconds.
      expect(
        store.upsertPosition(sessionId: 'b', lat: 0.1, lng: 0),
        PresenceOutcome.implausibleMovement,
      );

      // Ten minutes later the same place is reachable (50 m/s * 600 s).
      clock = clock.add(const Duration(minutes: 10));
      expect(
        store.upsertPosition(sessionId: 'b', lat: 0.1, lng: 0),
        PresenceOutcome.accepted,
      );
    });

    test('the selfie and the profile are fixed at session birth', () {
      store.upsertPosition(
        sessionId: 'b',
        lat: 0,
        lng: 0,
        selfieBase64: 'first',
        profile: const PresenceProfile(intent: 'chat'),
      );
      store.upsertPosition(
        sessionId: 'b',
        lat: 0,
        lng: 0,
        selfieBase64: 'second',
        profile: const PresenceProfile(intent: 'friendship'),
      );

      expect(store.selfieBase64For('b'), 'first');
      expect(store.profileFor('b')!.intent, 'chat');
    });

    test('nearby people come sorted from the closest distance band', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'far', lat: 0.0008, lng: 0);
      store.upsertPosition(sessionId: 'near', lat: 0.0001, lng: 0);
      store.upsertPosition(sessionId: 'mid', lat: 0.0004, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final result = store.nearbyPeople(sessionId: 'a', radiusMeters: 100)!;

      expect(result.map((p) => p.sessionId), ['near', 'mid', 'far']);
    });

    group('the viewer must stay put too, distances go anchor to anchor', () {
      // ~1 m in degrees of latitude (and of longitude at the equator).
      const metersToDeg = 1 / 111320;

      /// Una lettura ogni [SessionStore.minPositionInterval]: la frequenza
      /// massima che il server usa davvero.
      void readingAt(String id, double northMeters, [double eastMeters = 0]) {
        clock = clock.add(SessionStore.minPositionInterval);
        store.upsertPosition(
          sessionId: id,
          lat: northMeters * metersToDeg,
          lng: eastMeters * metersToDeg,
        );
      }

      bool sees(String viewer, String other) => store
          .nearbyPeople(sessionId: viewer, radiusMeters: 100)!
          .any((p) => p.sessionId == other);

      test('after a confirmed move the viewer sees nobody for a minute, and '
          'nobody sees the viewer', () {
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
        store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
        clock = clock.add(const Duration(minutes: 5));
        expect(sees('a', 'b'), isTrue);

        // 'a' moves 70 m: still well within 100 m of 'b', but a real move.
        for (var i = 0; i < 3; i++) {
          readingAt('a', 70);
        }
        expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isEmpty);
        expect(sees('b', 'a'), isFalse);

        clock = clock.add(const Duration(seconds: 59));
        expect(store.nearbyPeople(sessionId: 'a', radiusMeters: 100), isEmpty);
        clock = clock.add(const Duration(seconds: 1));
        expect(sees('a', 'b'), isTrue);
        expect(sees('b', 'a'), isTrue);
      });

      test('small steps along the edge of the circle never change what the '
          'viewer sees, even far past the edge', () {
        store.upsertPosition(sessionId: 'target', lat: 0, lng: 0);
        clock = clock.add(const Duration(minutes: 10));
        store.upsertPosition(sessionId: 'a', lat: 95 * metersToDeg, lng: 0);
        clock = clock.add(const Duration(minutes: 1));
        expect(sees('a', 'target'), isTrue);

        // Ten minutes of 5 m steps back and forth across the 100 m edge,
        // then a slow walk out to 145 m: the raw position is often outside
        // the circle, but the anchor (95 m) stays where it was.
        final changes = <bool>[];
        var last = true;
        for (var i = 0; i < 60; i++) {
          final north = i < 50 ? 95.0 + 5 * (i % 3) : 95.0 + 5 * (i - 49);
          readingAt('a', north);
          final now = sees('a', 'target');
          if (now != last) changes.add(now);
          last = now;
        }

        expect(changes, isEmpty);
      });

      test('forcing anchor resets yields at most one sample per confirmed '
          'move plus a minute of waiting', () {
        store.upsertPosition(sessionId: 'target', lat: 0, lng: 0);
        // 'witness' is within 100 m of both probing spots: a non-empty list
        // means "the viewer got an answer", whatever the answer about
        // 'target' is.
        store.upsertPosition(
          sessionId: 'witness',
          lat: 130 * metersToDeg,
          lng: 0,
        );
        clock = clock.add(const Duration(minutes: 10));
        const inside = 95.0; // sees 'target'
        const outside = 165.0; // 70 m further: a real move, past the edge
        store.upsertPosition(sessionId: 'a', lat: inside * metersToDeg, lng: 0);

        // The best a prober can do: as soon as it gets an answer, hop to the
        // other spot, one reading every 10 s, for 15 minutes.
        final start = clock;
        final answers = <(DateTime, bool)>[];
        var spot = inside;
        var waiting = true;
        for (var i = 0; i < 90; i++) {
          readingAt('a', spot);
          final list = store.nearbyPeople(sessionId: 'a', radiusMeters: 100)!;
          if (waiting && list.isNotEmpty) {
            answers.add((clock, list.any((p) => p.sessionId == 'target')));
            spot = spot == inside ? outside : inside;
          }
          waiting = list.isEmpty;
        }

        expect(answers.length, greaterThanOrEqualTo(5));
        // It is still an oracle (each answer is right)...
        for (final (index, (_, seesTarget)) in answers.indexed) {
          expect(seesTarget, index.isEven);
        }
        // ...but a slow one: never two answers less than a minute plus the
        // readings to confirm the move apart. Before, every single reading
        // (or every 0.5 s broadcast) was an answer.
        for (var i = 1; i < answers.length; i++) {
          expect(
            answers[i].$1.difference(answers[i - 1].$1),
            greaterThanOrEqualTo(const Duration(seconds: 80)),
          );
        }
        expect(
          answers.length,
          lessThanOrEqualTo(clock.difference(start).inSeconds ~/ 80 + 1),
        );
      });

      test('indoor GPS jitter of 20-50 m, with a bad first fix, never resets '
          'anyone nor empties the list', () {
        // A phone left on a table: every reading is 20-50 m off the real
        // spot, in changing directions, sometimes twice on the same side.
        // The first fix is 50 m off: with an anchor fixed on it (the old
        // rule) a reading 45 m on the other side was already 95 m "away".
        const jitter = <(double, double)>[
          (-45, 0), (0, 40), (0, -40), (30, -30), (-30, 30), (20, 0), //
          (-50, 0), (-50, 0), (0, 50), (0, 50), (35, 35), (-35, -35),
        ];
        store
          ..upsertPosition(sessionId: 'a', lat: 0, lng: 50 * metersToDeg)
          ..upsertPosition(sessionId: 'b', lat: 0, lng: -50 * metersToDeg);
        final bArrivedAt = store.allSessions
            .firstWhere((s) => s.sessionId == 'b')
            .arrivedAt;

        // Half an hour, a reading every 10 s each.
        for (var i = 0; i < 180; i++) {
          final (east, north) = jitter[i % jitter.length];
          readingAt('a', north, east);
          store.upsertPosition(
            sessionId: 'b',
            lat: -north * metersToDeg,
            lng: -east * metersToDeg,
          );
          if (clock.difference(bArrivedAt) >= const Duration(minutes: 1)) {
            expect(sees('a', 'b'), isTrue, reason: 'reading $i');
            expect(sees('b', 'a'), isTrue, reason: 'reading $i');
          }
        }

        final b = store.allSessions.firstWhere((s) => s.sessionId == 'b');
        expect(b.arrivedAt, bArrivedAt);
        expect(
          store
              .nearbyPeople(sessionId: 'a', radiusMeters: 100)!
              .single
              .meetingChance,
          MeetingChance.high,
        );
      });

      test('positions closer than the rate limit are ignored, the unlock '
          'token they carry is not', () {
        store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
        clock = clock.add(const Duration(seconds: 9));

        expect(
          store.upsertPosition(
            sessionId: 'b',
            lat: 0.0001,
            lng: 0,
            unlockToken: 'token',
          ),
          PresenceOutcome.tooSoon,
        );
        final b = store.allSessions.single;
        expect(b.lat, 0);
        expect(store.unlockTokenFor('b'), 'token');

        clock = clock.add(const Duration(seconds: 1));
        expect(
          store.upsertPosition(sessionId: 'b', lat: 0.0001, lng: 0),
          PresenceOutcome.accepted,
        );
        expect(b.lat, 0.0001);
      });
    });

    test('within a distance band the order is fixed per viewer, not by the '
        'exact distance', () {
      const metersToDeg = 1 / 111320;
      List<String> orderSeenBy(Map<String, double> metersNorth) {
        clock = DateTime(2026, 1, 1);
        store = SessionStore.withClock(() => clock);
        store.upsertPosition(sessionId: 'viewer', lat: 0, lng: 0);
        for (final MapEntry(:key, :value) in metersNorth.entries) {
          store.upsertPosition(
            sessionId: key,
            lat: value * metersToDeg,
            lng: 0,
          );
        }
        clock = clock.add(const Duration(minutes: 5));
        return store
            .nearbyPeople(sessionId: 'viewer', radiusMeters: 100)!
            .map((p) => p.sessionId)
            .toList();
      }

      // p1-p4 in the first 25 m band, 'far' in the third one.
      final first = orderSeenBy({
        'p1': 3,
        'p2': 9,
        'p3': 16,
        'p4': 23,
        'far': 60,
      });
      final shuffled = orderSeenBy({
        'p1': 23,
        'p2': 3,
        'p3': 9,
        'p4': 16,
        'far': 55,
      });

      expect(first, shuffled);
      expect(first.last, 'far');
      expect(first.take(4), unorderedEquals(['p1', 'p2', 'p3', 'p4']));
    });

    test('the debug snapshot exposes no distances between people', () {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0.0001, lng: 0);

      final snapshot = store.debugSnapshot();

      for (final entry in snapshot) {
        expect(entry.keys, isNot(contains('distanceMetersToOthers')));
      }
    });

    group('with an active hotspot', () {
      late HotspotStore hotspots;

      setUp(() {
        hotspots = HotspotStore.withClock(() => clock);
      });

      test(
        'widens visibility beyond radiusMeters for two people it covers',
        () {
          store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
          store.upsertPosition(sessionId: 'b', lat: 0.0001, lng: 0);
          store.upsertPosition(sessionId: 'c', lat: 0, lng: 0.0001);
          clock = clock.add(const Duration(minutes: 16));
          hotspots.detectAndRefresh(store.allSessions);

          // ~150m from the trio's centroid: too far from 'a' individually
          // under the 100m radius, but within the hotspot's 200m reach.
          store.upsertPosition(
            sessionId: 'd',
            lat: 0.00003 + 0.00135,
            lng: 0.00003,
          );
          clock = clock.add(const Duration(minutes: 2));

          final result = store.nearbyPeople(
            sessionId: 'a',
            radiusMeters: 100,
            hotspotStore: hotspots,
          )!;

          expect(result.map((p) => p.sessionId), contains('d'));
        },
      );

      test('never widens visibility without an injected/active hotspot', () {
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
        store.upsertPosition(sessionId: 'b', lat: 0.0001, lng: 0);
        store.upsertPosition(sessionId: 'c', lat: 0, lng: 0.0001);
        store.upsertPosition(
          sessionId: 'd',
          lat: 0.00003 + 0.00135,
          lng: 0.00003,
        );
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

      void placeViewerAndSix({String unlockToken = ''}) {
        // 'a' is the viewer. Six others at clearly increasing distances
        // (~11m apart), each with a distinct selfie so the free/locked
        // split is unambiguous to check by content.
        store.upsertPosition(
          sessionId: 'a',
          lat: 0,
          lng: 0,
          unlockToken: unlockToken,
        );
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

      test('a viewer with no linked device is treated as locked -- the '
          'closest two thirds arrive with no selfie', () {
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
      });

      test(
        'locked people are flagged and keep their meeting chance -- only the '
        'photo is paywalled, never that',
        () {
          placeViewerAndSix();

          final result = store.nearbyPeople(
            sessionId: 'a',
            radiusMeters: 1000,
            paywallStore: paywall,
          )!;

          final locked = result.firstWhere((p) => p.sessionId == 'p1');
          expect(locked.selfieBase64, isEmpty);
          expect(locked.locked, isTrue);
          expect(locked.meetingChance, MeetingChance.high);
          final json = locked.toJson(personId: 'x');
          expect(json['locked'], isTrue);
          expect(json.keys, isNot(contains('selfieBase64')));
          expect(json.keys, isNot(contains('distanceMeters')));
          // The free ones are flagged as such.
          expect(
            result.where((p) => !p.locked).map((p) => p.sessionId),
            unorderedEquals(['p5', 'p6']),
          );
        },
      );

      test('a viewer with a valid unlock token sees every selfie', () {
        placeViewerAndSix(unlockToken: paywall.issueUnlockToken());

        final result = store.nearbyPeople(
          sessionId: 'a',
          radiusMeters: 1000,
          paywallStore: paywall,
        )!;

        for (final person in result) {
          expect(person.selfieBase64, isNotEmpty);
        }
      });

      test("someone else's purchase does nothing for this viewer, and an "
          'invented token unlocks nothing', () {
        paywall.issueUnlockToken();
        placeViewerAndSix(unlockToken: 'not-a-real-token');

        final result = store.nearbyPeople(
          sessionId: 'a',
          radiusMeters: 1000,
          paywallStore: paywall,
        )!;

        expect(result.where((p) => p.selfieBase64.isEmpty), hasLength(4));
      });

      test('never blanks below the 2-free minimum, even on a short list', () {
        store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
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
