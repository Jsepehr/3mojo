import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/paywall/domain/usecases/get_locked_nearby_people_usecase.dart';

NearbyPerson _person(String id, {bool isLocked = false}) =>
    NearbyPerson(id: id, meetingChance: MeetingChance.low, isLocked: isLocked);

void main() {
  const useCase = GetLockedNearbyPeopleUseCase();

  group('GetLockedNearbyPeopleUseCase', () {
    test('follows the lock decided by the server, without recomputing it', () {
      // The server sends the list nearest first: the two closest locked.
      final people = [
        _person('nearest', isLocked: true),
        _person('near', isLocked: true),
        _person('far'),
      ];

      final result = useCase(people, isUnlocked: false);

      expect(
        {for (final entry in result) entry.person.id: entry.isLocked},
        {'nearest': true, 'near': true, 'far': false},
      );
    });

    test('nothing is shown as locked once unlocked on this phone', () {
      final people = [_person('a', isLocked: true), _person('b')];

      final result = useCase(people, isUnlocked: true);

      expect(result.map((r) => r.isLocked), everyElement(isFalse));
    });

    test('lists free people first, then locked, keeping the server order '
        'inside each group', () {
      final people = [
        _person('l1', isLocked: true),
        _person('f1'),
        _person('l2', isLocked: true),
        _person('f2'),
      ];

      final result = useCase(people, isUnlocked: false);

      expect(result.map((r) => r.person.id), ['f1', 'f2', 'l1', 'l2']);
    });
  });
}
