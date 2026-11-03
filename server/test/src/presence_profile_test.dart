import 'package:test/test.dart';
import 'package:threemojo_server/src/presence_profile.dart';

void main() {
  group('PresenceProfile.fromJson', () {
    test('keeps valid values', () {
      final profile = PresenceProfile.fromJson({
        'gender': 'female',
        'lookingFor': ['male', 'nonBinary'],
        'place': 'club',
        'languages': ['it', 'en'],
        'showGender': true,
      });

      expect(profile.gender, 'female');
      expect(profile.lookingFor, {'male', 'nonBinary'});
      expect(profile.place, 'club');
      expect(profile.languages, ['it', 'en']);
      expect(profile.visibleGender, 'female');
    });

    test('turns anything outside the closed lists into neutral values', () {
      final profile = PresenceProfile.fromJson({
        'gender': '<script>',
        'lookingFor': ['unspecified', 42, 'robots'],
        'place': 'Bar Sport, via Roma 3',
        'languages': ['it', 'en', 'es', 'ENGLISH', 'xyz'],
        'showGender': true,
      });

      expect(profile.gender, PresenceProfile.unspecified);
      expect(profile.lookingFor, PresenceProfile.searchableGenders);
      expect(profile.place, PresenceProfile.otherPlace);
      expect(profile.languages, ['it', 'en']);
      // "Show my gender" means nothing for an unspecified gender.
      expect(profile.visibleGender, isNull);
    });

    test(
      'a missing place (older clients, or the old intent field) is other',
      () {
        expect(
          PresenceProfile.fromJson({'intent': 'chat'}).place,
          PresenceProfile.otherPlace,
        );
        expect(PresenceProfile.fromJson({}).place, PresenceProfile.otherPlace);
      },
    );

    test('every place of the closed list is kept', () {
      for (final place in PresenceProfile.places) {
        expect(PresenceProfile.fromJson({'place': place}).place, place);
      }
      expect(PresenceProfile.places, {
        'bar',
        'discoPub',
        'cafe',
        'club',
        'event',
        'outdoors',
        'other',
      });
    });

    test('languages come only from the closed list shared with the app', () {
      final profile = PresenceProfile.fromJson({
        'languages': ['xx', 'qq', 'de'],
      });

      expect(profile.languages, ['de']);
    });

    test('a missing profile is the anonymous one', () {
      final profile = PresenceProfile.fromJson({});

      expect(profile.gender, PresenceProfile.unspecified);
      expect(profile.lookingFor, PresenceProfile.searchableGenders);
      expect(profile.visibleGender, isNull);
    });
  });

  group('mutuallyCompatible', () {
    test('needs both sides to accept the other', () {
      const manForWomen = PresenceProfile(
        gender: 'male',
        lookingFor: {'female'},
      );
      const womanForWomen = PresenceProfile(
        gender: 'female',
        lookingFor: {'female'},
      );
      const womanForMen = PresenceProfile(
        gender: 'female',
        lookingFor: {'male'},
      );

      expect(
        PresenceProfile.mutuallyCompatible(manForWomen, womanForWomen),
        isFalse,
      );
      expect(
        PresenceProfile.mutuallyCompatible(manForWomen, womanForMen),
        isTrue,
      );
    });
  });
}
