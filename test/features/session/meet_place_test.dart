import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/session/domain/entities/meet_place.dart';
import 'package:threemojo_app/features/session/presentation/meet_place_labels.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

void main() {
  test('the closed list is exactly the seven codes shared with the server', () {
    expect(MeetPlace.values.map((p) => p.name), [
      'bar',
      'discoPub',
      'cafe',
      'club',
      'event',
      'outdoors',
      'other',
    ]);
  });

  test(
    '"other" is the fallback and the only one that is not a declaration',
    () {
      expect(MeetPlace.fallback, MeetPlace.other);
      expect(MeetPlace.other.isDeclared, isFalse);
      for (final place in MeetPlace.values.where((p) => p != MeetPlace.other)) {
        expect(place.isDeclared, isTrue);
      }
    },
  );

  test(
    'every place has an emoji and a translated label in every language',
    () async {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = await AppLocalizations.delegate.load(locale);
        final labels = <String>{};
        for (final place in MeetPlace.values) {
          expect(MeetPlaceLabels.emoji(place), isNotEmpty);
          final label = MeetPlaceLabels.label(l10n, place);
          expect(label, isNotEmpty);
          labels.add(label);
        }
        expect(labels, hasLength(MeetPlace.values.length));
      }
    },
  );
}
