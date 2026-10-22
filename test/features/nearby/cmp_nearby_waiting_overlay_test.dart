import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/nearby/presentation/widgets/cmp_nearby_waiting_overlay.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('the first tip says that the viewer too must stay put for a '
      'minute: an empty list right after Start is expected, not a bug', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: CmpNearbyWaitingOverlay(title: 'title')),
      ),
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.you_too_must_stay_put_for_a_minute), findsOneWidget);

    // Il radar anima all'infinito e i suggerimenti ruotano con un timer:
    // smontare il widget li ferma.
    await tester.pumpWidget(const SizedBox());
  });
}
