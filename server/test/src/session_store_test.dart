import 'package:test/test.dart';
import 'package:threemojo_server/src/meeting_chance.dart';
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
  });
}
