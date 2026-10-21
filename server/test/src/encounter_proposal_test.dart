import 'package:test/test.dart';
import 'package:threemojo_server/src/encounter_proposal.dart';

void main() {
  group('EncounterProposal.parse', () {
    test('keeps every code of the closed list', () {
      for (final code in EncounterProposal.values) {
        expect(EncounterProposal.parse(code), code);
      }
    });

    test('a missing value (older clients) falls back to getToKnow', () {
      expect(EncounterProposal.parse(null), EncounterProposal.getToKnow);
    });

    test('an unknown code, free text or a non-string falls back to '
        'getToKnow', () {
      for (final raw in <Object?>['dance', 'Wants to dance', '', 42, true]) {
        expect(EncounterProposal.parse(raw), EncounterProposal.getToKnow);
      }
    });

    test('the closed list is exactly the five codes shared with the app', () {
      expect(EncounterProposal.values, {
        'sayHi',
        'chat',
        'friendship',
        'getToKnow',
        'drink',
      });
    });
  });
}
