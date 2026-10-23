import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/nearby/presentation/widgets/cmp_nearby_error_state.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('[${locale.languageCode}] "device not verified" has its own '
        'translated text, Retry and End', (tester) async {
      var retries = 0;
      var ends = 0;
      const failure = DeviceNotVerifiedFailure();
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CmpNearbyErrorState(
              failure: failure,
              isRetrying: false,
              onRetry: () => retries++,
              onOpenLocationSettings: () {},
              onOpenAppSettings: () {},
              onEndSession: () => ends++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(locale);

      expect(find.text(l10n.device_not_verified_title), findsOneWidget);
      expect(find.text(l10n.device_not_verified_body), findsOneWidget);
      expect(find.text(failure.message), findsNothing);
      expect(
        l10n.device_not_verified_title,
        isNot(l10n.nearby_error_generic_title),
      );

      for (final label in [l10n.retry, l10n.end_session]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
      }
      expect(retries, 1);
      expect(ends, 1);
    });
  }
}
