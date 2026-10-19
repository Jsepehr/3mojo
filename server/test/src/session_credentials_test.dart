import 'package:test/test.dart';
import 'package:threemojo_server/src/session_credentials.dart';

void main() {
  group('SessionCredentials', () {
    late SessionCredentials credentials;
    const secretA = '0f6a2c7e-1d3b-4c55-9a8e-7b2f4e6d8c10';
    const secretB = '9b1e5d3c-7a2f-4e60-8c4d-2f6a8b0c1e3d';

    setUp(() {
      credentials = SessionCredentials.empty();
    });

    test('the public id is stable for the same secret', () {
      expect(
        credentials.publicIdFor(secretA),
        credentials.publicIdFor(secretA),
      );
    });

    test('the public id never reveals the secret', () {
      final publicId = credentials.publicIdFor(secretA);

      expect(publicId, isNot(secretA));
      expect(publicId, isNot(contains(secretA)));
      expect(publicId, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('different secrets get different public ids', () {
      expect(
        credentials.publicIdFor(secretA),
        isNot(credentials.publicIdFor(secretB)),
      );
    });

    test('after forget, the same secret gets a fresh public id', () {
      final before = credentials.publicIdFor(secretA);

      credentials.forget(secretA);

      expect(credentials.publicIdFor(secretA), isNot(before));
    });

    test('forgetPublicId ends the link from the public side too', () {
      final before = credentials.publicIdFor(secretA);

      credentials.forgetPublicId(before);

      expect(credentials.knows(secretA), isFalse);
      expect(credentials.publicIdFor(secretA), isNot(before));
    });

    test('rejects missing, short or absurdly long secrets', () {
      expect(SessionCredentials.isValidSecret('x' * 129), isFalse);
      expect(SessionCredentials.isValidSecret(null), isFalse);
      expect(SessionCredentials.isValidSecret(''), isFalse);
      expect(SessionCredentials.isValidSecret('abc'), isFalse);
      expect(SessionCredentials.isValidSecret(secretA), isTrue);
    });
  });
}
