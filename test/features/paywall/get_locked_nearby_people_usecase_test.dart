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

    test('preserves the original order and every person exactly once', () {
      final people = [
        _personAt('far', 100),
        _personAt('near', 5),
        _personAt('mid', 50),
      ];

      final result = useCase(people, isUnlocked: false);

      expect(result.map((r) => r.person.id), ['far', 'near', 'mid']);
    });
  });
}
