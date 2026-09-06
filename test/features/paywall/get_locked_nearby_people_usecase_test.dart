import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/get_locked_nearby_people_usecase.dart';

NearbyPerson _personAt(String id, double distanceMeters) => NearbyPerson(
  id: id,
  photoUrl: '',
  distanceMeters: distanceMeters,
  meetingChance: MeetingChance.low,
);

void main() {
  const useCase = GetLockedNearbyPeopleUseCase();

  group('GetLockedNearbyPeopleUseCase', () {
    test('nothing is locked once unlocked', () {
      final people = [_personAt('a', 10), _personAt('b', 90)];

      final result = useCase(people, isUnlocked: true);

      expect(result.map((r) => r.isLocked), everyElement(isFalse));
    });

    test('the farthest third stays free, the rest is locked', () {
      // 9 people, 30m apart: a third farthest (60..90m) free, the closer
      // two thirds (0..50m) locked.
      final people = [
        for (var i = 0; i < 9; i++) _personAt('p$i', i * 10),
      ]..shuffle();

      final result = useCase(people, isUnlocked: false);

      final freeDistances =
          result.where((r) => !r.isLocked).map((r) => r.person.distanceMeters).toSet();
      final lockedDistances =
          result.where((r) => r.isLocked).map((r) => r.person.distanceMeters).toSet();

      expect(freeDistances, {60, 70, 80});
      expect(lockedDistances, {0, 10, 20, 30, 40, 50});
    });

    test('lists free people first, then locked, keeping every person', () {
      final people = [
        _personAt('near', 5),
        _personAt('far', 100),
        _personAt('mid', 50),
      ];

      final result = useCase(people, isUnlocked: false);

      // The minimum of 2 free people kicks in here (a third of 3 would
      // round down to 1): 'far' and 'mid' are the two farthest, so both are
      // free and move to the front; 'near' stays locked.
      expect(result.map((r) => r.person.id), ['far', 'mid', 'near']);
      expect(result.map((r) => r.isLocked), [false, false, true]);
    });

    test('never locks below minFreeCount, even on a short list', () {
      final people = [_personAt('a', 10), _personAt('b', 5)];

      final result = useCase(people, isUnlocked: false);

      // Only 2 people total: a plain third would free 0, but the minimum
      // of 2 free people means nobody ends up locked.
      expect(result.map((r) => r.isLocked), everyElement(isFalse));
    });

    test('the minimum can never free more people than actually exist', () {
      final people = [_personAt('only', 42)];

      final result = useCase(people, isUnlocked: false);

      expect(result, hasLength(1));
      expect(result.single.isLocked, isFalse);
    });
  });
}
