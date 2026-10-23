import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/config/privacy_policy_info.dart';
import 'package:threemojo_app/core/config/safety_contact.dart';
import 'package:threemojo_app/features/safety/presentation/pages/ui_privacy_policy.dart';
import 'package:threemojo_app/features/safety/presentation/pages/ui_terms_of_use.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

/// L'informativa privacy dentro l'app: tutte le sezioni, in ogni lingua,
/// con versione e data in cima e i contatti presi dalla configurazione.
void main() {
  Future<void> pump(WidgetTester tester, Widget page, Locale locale) async {
    // Alta abbastanza da costruire tutta la lista, anche le ultime sezioni.
    await tester.binding.setSurfaceSize(const Size(800, 12000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('[${locale.languageCode}] every section is there, with '
        'version, date and the configured contacts', (tester) async {
      final l10n = await AppLocalizations.delegate.load(locale);
      await pump(tester, const UiPrivacyPolicy(), locale);

      for (final title in [
        l10n.privacy_who_title,
        l10n.privacy_in_short_title,
        l10n.privacy_collect_title,
        l10n.privacy_bases_title,
        l10n.privacy_retention_title,
        l10n.privacy_moderation_title,
        l10n.privacy_sharing_title,
        l10n.privacy_rights_title,
        l10n.privacy_age_title,
        l10n.privacy_security_title,
        l10n.privacy_changes_title,
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      for (final item in [
        l10n.privacy_data_location_title,
        l10n.privacy_data_selfie_title,
        l10n.privacy_data_gender_title,
        l10n.privacy_data_chat_title,
        l10n.privacy_rights_withdraw,
      ]) {
        expect(find.text(item), findsOneWidget, reason: item);
      }

      expect(
        find.text(
          l10n.privacy_version_line(
            PrivacyPolicyInfo.version,
            PrivacyPolicyInfo.lastUpdated,
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining(PrivacyPolicyInfo.controller), findsOneWidget);
      expect(
        find.textContaining(PrivacyPolicyInfo.privacyEmail),
        findsOneWidget,
      );
      expect(find.textContaining(SafetyContact.email), findsWidgets);
      expect(find.textContaining(PrivacyPolicyInfo.publicUrl), findsOneWidget);
    });
  }

  testWidgets('the terms of use link to the privacy policy', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await pump(tester, const UiTermsOfUse(), const Locale('en'));

    await tester.tap(find.text(l10n.read_the_privacy_policy));
    await tester.pumpAndSettle();

    expect(find.byType(UiPrivacyPolicy), findsOneWidget);
  });
}
