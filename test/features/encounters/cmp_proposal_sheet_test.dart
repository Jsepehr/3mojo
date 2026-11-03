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

const _all = [
  EncounterProposal.chat,
  EncounterProposal.friendship,
  EncounterProposal.getToKnow,
  EncounterProposal.drink,
];

Finder _row(EncounterProposal proposal) =>
    find.byKey(ValueKey('proposal-${proposal.name}'));

void main() {
  testWidgets('the preselected proposal comes first, then the others in the '
      'order given — none hidden', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CmpProposalSheet(
          photoBytes: null,
          preselected: EncounterProposal.drink,
          proposals: _all,
          onChoose: (_) {},
        ),
      ),
    );

    final tops = [
      for (final proposal in _all)
        (proposal, tester.getTopLeft(_row(proposal)).dy),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    expect(tops.map((entry) => entry.$1), [
      EncounterProposal.drink,
      EncounterProposal.chat,
      EncounterProposal.friendship,
      EncounterProposal.getToKnow,
    ]);
    expect(find.text('Bere qualcosa'), findsOneWidget);
    expect(find.text('Vedrà la tua foto e questa frase'), findsOneWidget);
    // Righe grandi da toccare.
    for (final proposal in _all) {
      expect(tester.getSize(_row(proposal)).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('only the proposals of the own place are offered, none of '
      'the others', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CmpProposalSheet(
          photoBytes: null,
          preselected: EncounterProposal.dance,
          proposals: const [EncounterProposal.dance, EncounterProposal.drink],
          onChoose: (_) {},
        ),
      ),
    );

    expect(_row(EncounterProposal.dance), findsOneWidget);
    expect(_row(EncounterProposal.drink), findsOneWidget);
    expect(_row(EncounterProposal.chat), findsNothing);
    expect(_row(EncounterProposal.friendship), findsNothing);
    expect(find.text('Ballare'), findsOneWidget);
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
          preselected: EncounterProposal.chat,
          proposals: _all,
          onChoose: (_) {},
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('☕')), findsNothing);
    expect(
      tester.getSemantics(_row(EncounterProposal.chat)),
      matchesSemantics(
        label: 'Due chiacchiere',
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
                proposals: _all,
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
