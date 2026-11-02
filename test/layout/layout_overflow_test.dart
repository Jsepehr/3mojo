import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:threemojo_app/features/encounters/presentation/pages/ui_active_match.dart';
import 'package:threemojo_app/features/encounters/presentation/pages/ui_encounters.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_proposal.dart';
import 'package:threemojo_app/features/encounters/presentation/widgets/cmp_proposal_sheet.dart';
import 'package:threemojo_app/features/nearby/presentation/widgets/cmp_nearby_person_tile.dart';
import 'package:threemojo_app/features/nearby/presentation/widgets/cmp_nearby_waiting_overlay.dart';
import 'package:threemojo_app/features/safety/presentation/pages/ui_privacy_policy.dart';
import 'package:threemojo_app/features/safety/presentation/pages/ui_safety.dart';
import 'package:threemojo_app/features/safety/presentation/pages/ui_terms_of_use.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import '../support/layout_harness.dart';

/// Nessuna pagina deve andare in overflow su un telefono stretto (360 dp),
/// con il testo ingrandito (2x) e in arabo (RTL), né in orizzontale. Un
/// overflow è un `FlutterError` e fa fallire il test: niente `expect`
/// necessari oltre a quelli per arrivare alla pagina.
void main() {
  setUpAll(loadAppFonts);

  for (final layout in layoutCases) {
    group(layout.name, () {
      late AppLocalizations l10n;
      late LayoutWorld world;

      setUp(() async {
        l10n = await AppLocalizations.delegate.load(layout.locale);
        world = LayoutWorld(layout.language);
      });

      Future<void> pumpApp(WidgetTester tester) async {
        applyLayoutCase(tester, layout);
        await tester.pumpWidget(world.build());
        await advance(tester, const Duration(milliseconds: 300));
      }

      Future<void> tapVisible(WidgetTester tester, Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
        await advance(tester, const Duration(milliseconds: 600));
      }

      /// La prima persona non bloccata dal paywall: con testo grande può
      /// stare sotto la piega (e la lista costruisce solo ciò che è vicino).
      Future<Finder> freePerson(WidgetTester tester) async {
        final free = find.byWidgetPredicate(
          (widget) => widget is CmpNearbyPersonTile && !widget.isLocked,
        );
        final list = find.byType(ListView).first;
        for (var i = 0; i < 30 && free.evaluate().isEmpty; i++) {
          await tester.drag(list, const Offset(0, -200));
          await tester.pump(const Duration(milliseconds: 100));
        }
        return free.first;
      }

      Future<void> enterDemo(WidgetTester tester) async {
        await tapVisible(tester, find.text(l10n.demo_try_link));
        expect(find.text(l10n.demo_banner_title), findsOneWidget);
      }

      testWidgets('home offline and drawer', (tester) async {
        await pumpApp(tester);
        expect(find.text(l10n.start), findsOneWidget);

        tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
        await advance(tester);
        expect(find.text(l10n.my_profile), findsOneWidget);
      });

      testWidgets('home online (demo) with the paywall banner, the '
          'requests page and the proposal sheet', (tester) async {
        await pumpApp(tester);
        await enterDemo(tester);

        expect(find.text(l10n.demo_unlock_button), findsOneWidget);

        // Tendina "Cosa vuoi proporre?" su una persona libera.
        await tapVisible(tester, await freePerson(tester));
        expect(find.byKey(const ValueKey('proposal-chat')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('proposal-chat')));
        await advance(tester, const Duration(milliseconds: 600));

        // Richieste.
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold).first),
        ).clearSnackBars();
        await advance(tester);
        await tester.tap(find.byTooltip(l10n.requests));
        await advance(tester);
        expect(find.byType(UiEncounters), findsOneWidget);
      });

      testWidgets('match chat page (demo), with messages and the '
          'not-sent state', (tester) async {
        await pumpApp(tester);
        await enterDemo(tester);

        await tapVisible(tester, await freePerson(tester));
        await tester.tap(find.byKey(const ValueKey('proposal-chat')));
        // Il "sì" simulato arriva dopo 3 s.
        await advance(tester, const Duration(seconds: 4));
        final match = find.byType(UiActiveMatch);
        expect(match, findsOneWidget);

        ScaffoldMessenger.of(tester.element(match)).clearSnackBars();
        await advance(tester);
        await tester.enterText(find.byType(TextField), 'Ciao!');
        await tester.tap(find.byIcon(Icons.send));
        await advance(tester, const Duration(seconds: 4));
        expect(
          find.textContaining('Ciao!', findRichText: true),
          findsOneWidget,
        );
      });

      testWidgets('profile form (onboarding)', (tester) async {
        world.profiles.saved = null;
        await pumpApp(tester);
        await advance(tester);
        expect(find.text(l10n.demo_try_link), findsOneWidget);
      });

      testWidgets('Start: location notice and selfie wizard', (tester) async {
        await pumpApp(tester);
        await tapVisible(tester, find.text(l10n.start));
        expect(find.text(l10n.location_disclosure_title), findsOneWidget);

        await tapVisible(tester, find.text(l10n.location_disclosure_continue));
        expect(find.text(l10n.take_a_selfie), findsOneWidget);

        await tapVisible(tester, find.text(l10n.take_a_selfie));
        expect(find.text(l10n.i_like_it_continue), findsOneWidget);
        await tapVisible(tester, find.text(l10n.i_like_it_continue));
      });

      testWidgets('privacy policy, terms of use and safety pages', (
        tester,
      ) async {
        PackageInfo.setMockInitialValues(
          appName: 'Raen',
          packageName: 'com.raen.app',
          version: '1.0.0',
          buildNumber: '1',
          buildSignature: '',
        );
        applyLayoutCase(tester, layout);
        for (final page in const <Widget>[
          UiPrivacyPolicy(),
          UiTermsOfUse(),
          UiSafety(),
        ]) {
          await tester.pumpWidget(layoutApp(layout, page));
          await advance(tester);
        }
      });

      testWidgets('waiting overlay of "Nearby" (empty list)', (tester) async {
        applyLayoutCase(tester, layout);
        await tester.pumpWidget(
          layoutApp(
            layout,
            Scaffold(
              body: CmpNearbyWaitingOverlay(
                title: l10n.no_one_nearby_right_now,
              ),
            ),
          ),
        );
        // Ogni suggerimento a rotazione (il più lungo decide l'altezza).
        for (var i = 0; i < 6; i++) {
          await advance(tester, const Duration(seconds: 6));
        }
      });

      testWidgets('proposal sheet alone, with every row', (tester) async {
        applyLayoutCase(tester, layout);
        await tester.pumpWidget(
          layoutApp(
            layout,
            Scaffold(
              body: CmpProposalSheet(
                photoBytes: null,
                preselected: EncounterProposal.drink,
                matchingTheirIntent: EncounterProposal.chat,
                onChoose: (_) {},
              ),
            ),
          ),
        );
        await advance(tester);
      });
    });
  }
}
