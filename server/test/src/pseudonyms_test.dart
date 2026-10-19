import 'package:test/test.dart';
import 'package:threemojo_server/src/pseudonyms.dart';

void main() {
  group('Pseudonyms', () {
    late Pseudonyms pseudonyms;

    setUp(() => pseudonyms = Pseudonyms());

    test('stable for a pair, different for each viewer', () {
      final forB = pseudonyms.idFor(viewerId: 'b', targetId: 'a');
      final forC = pseudonyms.idFor(viewerId: 'c', targetId: 'a');

      expect(pseudonyms.idFor(viewerId: 'b', targetId: 'a'), forB);
      expect(forB, isNot(forC));
      expect(forB, isNot('a'));
    });

    test('resolves only for the viewer that received it', () {
      final forB = pseudonyms.idFor(viewerId: 'b', targetId: 'a');

      expect(pseudonyms.resolve(viewerId: 'b', pseudonym: forB), 'a');
      expect(pseudonyms.resolve(viewerId: 'c', pseudonym: forB), isNull);
    });

    test('forget drops the session as viewer and as target', () {
      final aForB = pseudonyms.idFor(viewerId: 'b', targetId: 'a');
      final bForA = pseudonyms.idFor(viewerId: 'a', targetId: 'b');

      pseudonyms.forget('a');

      expect(pseudonyms.resolve(viewerId: 'b', pseudonym: aForB), isNull);
      expect(pseudonyms.resolve(viewerId: 'a', pseudonym: bForA), isNull);
    });
  });
}
