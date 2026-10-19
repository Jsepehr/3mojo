import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:threemojo_server/src/selfie_validator.dart';

Uint8List _jpeg({List<int> extraSegments = const []}) => Uint8List.fromList([
  0xFF, 0xD8, // SOI
  0xFF, 0xE0, 0x00, 0x07, 0x4A, 0x46, 0x49, 0x46, 0x00, // APP0 JFIF
  ...extraSegments,
  0xFF, 0xDB, 0x00, 0x03, 0x00, // DQT (kept)
  0xFF, 0xDA, 0x00, 0x04, 0x01, 0x02, // SOS
  0x10, 0x20, 0x30, // image data
  0xFF, 0xD9, // EOI
]);

const _exif = [0xFF, 0xE1, 0x00, 0x06, 0x45, 0x78, 0x69, 0x66];
const _comment = [0xFF, 0xFE, 0x00, 0x04, 0x68, 0x69];
const _icc = [0xFF, 0xE2, 0x00, 0x03, 0x01];

void main() {
  group('SelfieValidator', () {
    test('strips EXIF and comments, keeps the image and the color profile', () {
      final stripped = SelfieValidator.stripMetadata(
        _jpeg(extraSegments: [..._exif, ..._comment, ..._icc]),
      )!;

      expect(stripped, _jpeg(extraSegments: _icc));
    });

    test('a JPEG without metadata comes back unchanged', () {
      expect(SelfieValidator.stripMetadata(_jpeg()), _jpeg());
    });

    test('refuses anything that is not a JPEG', () {
      expect(
        SelfieValidator.stripMetadata(
          Uint8List.fromList(utf8.encode('GIF89a')),
        ),
        isNull,
      );
      // Truncated: no EOI.
      final truncated = _jpeg().sublist(0, 20);
      expect(SelfieValidator.stripMetadata(truncated), isNull);
      // Segment length pointing past the end of the file.
      expect(
        SelfieValidator.stripMetadata(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x7F, 0xFF, 0xFF, 0xD9]),
        ),
        isNull,
      );
    });

    test('refuses malformed base64 and oversized photos', () {
      expect(SelfieValidator.sanitizeBase64('not base64 at all!!'), isNull);

      final huge = Uint8List(SelfieValidator.maxBytes + 1)
        ..setAll(0, [0xFF, 0xD8]);
      expect(SelfieValidator.sanitizeBase64(base64Encode(huge)), isNull);
    });

    test('sanitizeBase64 returns the stripped photo in base64', () {
      final result = SelfieValidator.sanitizeBase64(
        base64Encode(_jpeg(extraSegments: _exif)),
      );

      expect(base64Decode(result!), _jpeg());
    });
  });
}
