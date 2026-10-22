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

  test('Android lists the native libraries outside pub, ML Kit with its '
      'terms', () async {
    final licenses = await licensesOn(TargetPlatform.android);

    expect(licenses.keys, [
      'Manrope',
      'Google ML Kit',
      'Google Play services',
      'AndroidX',
      'Tink',
      'Kotlin',
    ]);
    expect(
      licenses['Google ML Kit'],
      contains('https://developers.google.com/ml-kit/terms'),
    );
    expect(licenses['Tink'], contains('Apache License'));
  });

  test('iOS adds only the font: Vision is part of the system', () async {
    final licenses = await licensesOn(TargetPlatform.iOS);

    expect(licenses.keys, ['Manrope']);
  });
}
