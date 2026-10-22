import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/core/config/safety_contact.dart';
import '/l10n/generated/app_localizations.dart';
import 'ui_terms_of_use.dart';

/// "Sicurezza e segnalazioni" (dal menu laterale): come bloccare e
/// segnalare, cosa succede dopo (anche onestamente: il blocco dura fino a
/// End, niente account), cosa fare in pericolo, i termini d'uso e il
/// contatto pubblicato (`SafetyContact.email`, Apple guideline 1.2).
///
/// Il contatto si **mostra e si copia** negli appunti: l'app non include
/// `url_launcher`, e aprire un client di posta non è indispensabile.
class UiSafety extends StatelessWidget {
  const UiSafety({super.key});

  Future<void> _copyEmail(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(const ClipboardData(text: SafetyContact.email));
    HapticFeedback.selectionClick();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.email_copied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    Widget section(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: theme.colorScheme.primary)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.safety_and_reports)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(l10n.safety_page_intro, style: theme.textTheme.bodyLarge),
            section(
              Icons.block,
              l10n.safety_how_to_block_title,
              l10n.safety_how_to_block_body,
            ),
            section(
              Icons.flag_outlined,
              l10n.safety_how_to_report_title,
              l10n.safety_how_to_report_body,
            ),
            section(
              Icons.info_outline,
              l10n.safety_no_accounts_title,
              l10n.safety_no_accounts_body,
            ),
            section(
              Icons.emergency_outlined,
              l10n.safety_in_danger_title,
              l10n.safety_in_danger_body,
            ),
            section(
              Icons.mail_outline,
              l10n.safety_contact_title,
              l10n.safety_contact_body,
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 40, top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      SafetyContact.email,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.copy_email,
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copyEmail(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.description_outlined),
              label: Text(l10n.terms_of_use),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const UiTermsOfUse())),
            ),
          ],
        ),
      ),
    );
  }
}
