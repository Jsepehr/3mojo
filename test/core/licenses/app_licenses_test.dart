import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/licenses/app_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, String>> licensesOn(TargetPlatform platform) async {
    final entries = await appLicenses(rootBundle, platform).toList();
    return {
      for (final entry in entries)
        entry.packages.single: entry.paragraphs
            .map((paragraph) => paragraph.text)
            .join('\n'),
    };
  }

  test('Manrope ships with its OFL text, on every platform', () async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      final licenses = await licensesOn(platform);

      expect(licenses['Manrope'], contains('SIL Open Font License'));
      expect(licenses['Manrope'], contains('The Manrope Project Authors'));
    }
  });

  test('Android lists the native libraries outside pub, the Google ones '
      'with their terms', () async {
    final licenses = await licensesOn(TargetPlatform.android);

    expect(licenses.keys, [
      'Manrope',
      'Google Play services',
      'Google Play Billing Library',
      'Google Play Integrity',
      'AndroidX',
      'Tink',
      'Kotlin',
    ]);
    expect(
      licenses['Google Play services'],
      contains('https://developer.android.com/studio/terms'),
    );
    expect(
      licenses['Google Play Integrity'],
      contains(
        'https://developer.android.com/google/play/integrity/overview#tos',
      ),
    );
    expect(licenses['Tink'], contains('Apache License'));
  });

  test('Android no longer ships ML Kit: faces are found by the system '
      'FaceDetector', () async {
    final licenses = await licensesOn(TargetPlatform.android);

    expect(licenses.keys, isNot(contains('Google ML Kit')));
    expect(licenses.values.join('\n'), isNot(contains('mlkit')));
  });

  test('iOS adds only the font: Vision is part of the system', () async {
    final licenses = await licensesOn(TargetPlatform.iOS);

    expect(licenses.keys, ['Manrope']);
  });
}
