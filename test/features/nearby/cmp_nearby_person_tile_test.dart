import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/theme/app_theme.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/nearby/presentation/widgets/cmp_nearby_person_tile.dart';
import 'package:threemojo_app/features/session/domain/entities/meet_place.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('it'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('shows the declared place as a small label', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const CmpNearbyPersonTile(
          person: NearbyPerson(
            id: 'p',
            meetingChance: MeetingChance.low,
            place: MeetPlace.bar,
          ),
        ),
      ),
    );

    expect(find.text('🍺 Bar o pub'), findsOneWidget);
  });

  testWidgets('with place "other" nothing is shown about the place', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const CmpNearbyPersonTile(
          person: NearbyPerson(id: 'p', meetingChance: MeetingChance.low),
        ),
      ),
    );

    expect(find.textContaining('📍'), findsNothing);
    expect(find.text('Altro / preferisco non dirlo'), findsNothing);
  });

  testWidgets('the emoji of the place is not read by the screen reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(
        const CmpNearbyPersonTile(
          person: NearbyPerson(
            id: 'p',
            meetingChance: MeetingChance.low,
            place: MeetPlace.club,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('🪩')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Discoteca o club')), findsWidgets);
    semantics.dispose();
  });
}
