import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/encounters/domain/entities/encounter_proposal.dart';
import 'package:threemojo_app/features/encounters/presentation/widgets/cmp_proposal_sheet.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('it'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Finder _row(EncounterProposal proposal) =>
    find.byKey(ValueKey('proposal-${proposal.name}'));

void main() {
  testWidgets('the preselected proposal comes first, then the others in the '
      'order of the closed list — none hidden', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CmpProposalSheet(
          photoBytes: null,
          preselected: EncounterProposal.drink,
          onChoose: (_) {},
        ),
      ),
    );

    final tops = [
      for (final proposal in EncounterProposal.values)
        (proposal, tester.getTopLeft(_row(proposal)).dy),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    expect(tops.map((entry) => entry.$1), [
      EncounterProposal.drink,
      EncounterProposal.sayHi,
      EncounterProposal.chat,
      EncounterProposal.friendship,
      EncounterProposal.getToKnow,
    ]);
    expect(find.text('Bere qualcosa'), findsOneWidget);
    expect(find.text('Vedrà la tua foto e questa frase'), findsOneWidget);
    // Righe grandi da toccare.
    for (final proposal in EncounterProposal.values) {
      expect(tester.getSize(_row(proposal)).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('"in line with what they look for" marks only the proposal '
      'matching their public intent', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CmpProposalSheet(
          photoBytes: null,
          preselected: EncounterProposal.getToKnow,
          matchingTheirIntent: EncounterProposal.chat,
          onChoose: (_) {},
        ),
      ),
    );

    final mark = find.text('In linea con ciò che cerca');
    expect(mark, findsOneWidget);
    expect(
      find.descendant(of: _row(EncounterProposal.chat), matching: mark),
      findsOneWidget,
    );
  });

  testWidgets('without a public intent there is no mark', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CmpProposalSheet(
          photoBytes: null,
          preselected: EncounterProposal.getToKnow,
          onChoose: (_) {},
        ),
      ),
    );

    expect(find.text('In linea con ciò che cerca'), findsNothing);
  });

  testWidgets('the emoji is not read by the screen reader, the label is', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(
        CmpProposalSheet(
          photoBytes: null,
          preselected: EncounterProposal.sayHi,
          onChoose: (_) {},
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('👋')), findsNothing);
    expect(
      tester.getSemantics(_row(EncounterProposal.sayHi)),
      matchesSemantics(
        label: 'Salutare',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        onTapHint: 'Invia la richiesta',
      ),
    );
    semantics.dispose();
  });

  testWidgets('tapping a proposal sends it and closes the sheet', (
    tester,
  ) async {
    EncounterProposal? chosen;
    var closed = false;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              chosen = await showProposalSheet(
                context,
                photoBytes: null,
                preselected: EncounterProposal.getToKnow,
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Cosa vuoi proporre?'), findsOneWidget);

    await tester.tap(_row(EncounterProposal.friendship));
    await tester.pumpAndSettle();

    expect(chosen, EncounterProposal.friendship);
    expect(closed, isTrue);
    expect(find.text('Cosa vuoi proporre?'), findsNothing);
  });
}
