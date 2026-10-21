import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/encounters/domain/entities/encounter_proposal.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/encounters/presentation/widgets/cmp_incoming_request_tile.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('it'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

EncounterRequest _request(EncounterProposal proposal, {MeetIntent? intent}) =>
    EncounterRequest(
      id: 'r1',
      otherPersonId: 'p',
      status: EncounterRequestStatus.pending,
      proposal: proposal,
      otherIntent: intent,
      otherLanguages: const ['it'],
    );

void main() {
  testWidgets('shows the proposal as the main line, with "No, thanks" and a '
      'neutral yes', (tester) async {
    var accepted = false;
    var declined = false;
    await tester.pumpWidget(
      _wrap(
        CmpIncomingRequestTile(
          request: _request(EncounterProposal.drink),
          onAccept: () => accepted = true,
          onDecline: () => declined = true,
        ),
      ),
    );

    expect(find.text('Vuole bere qualcosa insieme a te'), findsOneWidget);
    expect(find.text('🥤'), findsOneWidget);
    expect(find.text('Questa persona vuole conoscerti'), findsNothing);
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('No, grazie'));
    await tester.tap(find.text('Sì'));
    expect(declined, isTrue);
    expect(accepted, isTrue);
  });

  testWidgets('hides the intent chip when it has the same emoji as the '
      'proposal', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CmpIncomingRequestTile(
          request: _request(EncounterProposal.chat, intent: MeetIntent.chat),
          onAccept: () {},
          onDecline: () {},
        ),
      ),
    );

    expect(find.text('Vuole fare due chiacchiere con te'), findsOneWidget);
    // Il chip "☕ Due chiacchiere" direbbe la stessa cosa: non c'è.
    expect(find.textContaining('☕ '), findsNothing);
    // Le lingue restano.
    expect(find.text('IT'), findsOneWidget);
  });

  testWidgets('keeps the intent chip when it says something else', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CmpIncomingRequestTile(
          request: _request(
            EncounterProposal.drink,
            intent: MeetIntent.friendship,
          ),
          onAccept: () {},
          onDecline: () {},
        ),
      ),
    );

    expect(find.text('🤝 Amicizia'), findsOneWidget);
  });
}
