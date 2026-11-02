import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/config/app_update_config.dart';
import 'package:threemojo_app/core/config/protocol_config.dart';

void main() {
  test('the store URLs are placeholders until configured: nothing is shown '
      'rather than a broken link', () {
    expect(AppUpdateConfig.iosStoreUrl, contains('TODO_REPLACE'));
    expect(AppUpdateConfig.androidStoreUrl, contains('TODO_REPLACE'));
    expect(AppUpdateConfig.storeUrlFor(TargetPlatform.iOS), isNull);
    expect(AppUpdateConfig.storeUrlFor(TargetPlatform.android), isNull);
  });

  test('web and desktop have no store', () {
    expect(AppUpdateConfig.storeUrlFor(TargetPlatform.macOS), isNull);
    expect(
      AppUpdateConfig.storeUrlFor(TargetPlatform.iOS, isWeb: true),
      isNull,
    );
  });

  test('the protocol version is declared once, aligned with the server', () {
    // server/lib/src/protocol_version.dart: ProtocolPolicy.currentVersion.
    expect(ProtocolConfig.version, 1);
    expect(ProtocolConfig.httpHeader, 'X-Raen-Protocol');
    expect(ProtocolConfig.closeCodeUpdateRequired, 4012);
  });
}
