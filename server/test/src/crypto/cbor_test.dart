import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:threemojo_server/src/crypto/cbor.dart';

Object? _decode(List<int> bytes) => Cbor.decode(Uint8List.fromList(bytes));

Matcher get _rejected => throwsA(isA<FormatException>());

void main() {
  group('Cbor.decode', () {
    test('reads the RFC 8949 examples it supports', () {
      expect(_decode([0x00]), 0);
      expect(_decode([0x17]), 23);
      expect(_decode([0x18, 0x18]), 24);
      expect(_decode([0x19, 0x03, 0xe8]), 1000);
      expect(_decode([0x1a, 0x00, 0x0f, 0x42, 0x40]), 1000000);
      expect(_decode([0x20]), -1);
      expect(_decode([0x38, 0x63]), -100);
      expect(_decode([0x43, 0x01, 0x02, 0x03]), [1, 2, 3]);
      expect(_decode([0x64, 0x49, 0x45, 0x54, 0x46]), 'IETF');
      expect(_decode([0x83, 0x01, 0x02, 0x03]), [1, 2, 3]);
      expect(_decode([0xf4]), false);
      expect(_decode([0xf5]), true);
      expect(_decode([0xf6]), isNull);
    });

    test('a map with text and negative integer keys (COSE)', () {
      // {"fmt": "x", -1: h'01'}
      final value = _decode([
        0xa2,
        0x63,
        0x66,
        0x6d,
        0x74,
        0x61,
        0x78,
        0x20,
        0x41,
        0x01,
      ]);
      expect(value, isA<Map<Object, Object?>>());
      final map = value! as Map;
      expect(map['fmt'], 'x');
      expect(map[-1], [1]);
      expect(map[-1], isA<Uint8List>());
    });

    test('rejects indefinite lengths, tags, floats and trailing bytes', () {
      expect(() => _decode([0x5f, 0x41, 0x01, 0xff]), _rejected);
      expect(() => _decode([0x9f, 0x01, 0xff]), _rejected);
      expect(() => _decode([0xc1, 0x1a, 0, 0, 0, 0]), _rejected);
      expect(() => _decode([0xf9, 0x3c, 0x00]), _rejected);
      expect(() => _decode([0x01, 0x02]), _rejected);
    });

    test('rejects truncated input without index errors', () {
      expect(() => _decode([]), _rejected);
      expect(() => _decode([0x19, 0x03]), _rejected);
      expect(() => _decode([0x43, 0x01]), _rejected);
      expect(() => _decode([0x83, 0x01]), _rejected);
      expect(() => _decode([0xa1, 0x01]), _rejected);
      // Una lunghezza enorme non alloca nulla.
      expect(() => _decode([0x9b, 0x7f, 0, 0, 0, 0, 0, 0, 0]), _rejected);
      expect(() => _decode([0x5a, 0xff, 0xff, 0xff, 0xff]), _rejected);
    });

    test('rejects repeated keys, non-scalar keys and invalid UTF-8', () {
      expect(() => _decode([0xa2, 0x01, 0x01, 0x01, 0x02]), _rejected);
      expect(() => _decode([0xa1, 0x80, 0x01]), _rejected);
      expect(() => _decode([0x62, 0xc3, 0x28]), _rejected);
    });

    test('rejects nesting deeper than maxDepth', () {
      final bytes = [for (var i = 0; i <= Cbor.maxDepth + 1; i++) 0x81, 0x01];
      expect(() => _decode(bytes), _rejected);
      final ok = [for (var i = 0; i < Cbor.maxDepth; i++) 0x81, 0x01];
      expect(_decode(ok), isA<List<Object?>>());
    });
  });
}
