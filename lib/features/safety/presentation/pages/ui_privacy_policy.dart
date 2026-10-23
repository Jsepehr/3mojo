import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/core/config/privacy_policy_info.dart';
import '/core/config/safety_contact.dart';
import '/l10n/generated/app_localizations.dart';

/// L'**informativa privacy** dentro l'app (Apple 5.1.1(i), Google Play,
/// artt. 13-14 GDPR): lo stesso contenuto di
/// `docs/privacy/informativa_bozza.md`, diviso in sezioni brevi, nelle lingue
/// dell'app (`privacy_*` negli ARB). In cima versione e data del testo
/// ([PrivacyPolicyInfo.version], [PrivacyPolicyInfo.lastUpdated]) e
/// l'indirizzo pubblico, che si copia con un tocco (l'app non include
/// `url_launcher`). Titolare e contatti vengono da [PrivacyPolicyInfo] e
/// [SafetyContact]: un solo posto da compilare.
///
/// Sta in `safety/` accanto ai termini d'uso (`UiTermsOfUse`): sono i due
/// testi "legali" dell'app, solo presentation, senza dati né regole propri.
/// Si apre dal menu, dal dialog "Informazioni", dal profilo (accanto al
/// consenso e ai termini) e dalla pagina dei termini.
///
/// Se il testo cambia nella sostanza va aggiornata anche la bozza (e
/// viceversa), e si alzano versione e data.
class UiPrivacyPolicy extends StatelessWidget {
  const UiPrivacyPolicy({super.key});

  Future<void> _copyUrl(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      const ClipboardData(text: PrivacyPolicyInfo.publicUrl),
    );
    HapticFeedback.selectionClick();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.link_copied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    const dpo = PrivacyPolicyInfo.dpoContact;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.privacy_policy)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              l10n.privacy_version_line(
                PrivacyPolicyInfo.version,
                PrivacyPolicyInfo.lastUpdated,
              ),
              style: muted,
            ),
            InkWell(
              onTap: () => _copyUrl(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l10n.privacy_online_copy(PrivacyPolicyInfo.publicUrl),
                  style: muted,
                ),
              ),
            ),
            _Section(
              key: const ValueKey('privacy_who'),
              icon: Icons.business_outlined,
              title: l10n.privacy_who_title,
              paragraphs: [
                l10n.privacy_who_body(
                  PrivacyPolicyInfo.controller,
                  PrivacyPolicyInfo.privacyEmail,
                  SafetyContact.email,
                ),
                if (dpo != null) l10n.privacy_who_dpo(dpo),
              ],
            ),
            _Section(
              key: const ValueKey('privacy_in_short'),
              icon: Icons.bolt_outlined,
              title: l10n.privacy_in_short_title,
              bullets: [
                l10n.privacy_in_short_no_accounts,
                l10n.privacy_in_short_visible,
                l10n.privacy_in_short_memory,
                l10n.privacy_in_short_no_ads,
              ],
            ),
            _Section(
              key: const ValueKey('privacy_collect'),
              icon: Icons.inventory_2_outlined,
              title: l10n.privacy_collect_title,
              items: [
                (
                  l10n.privacy_data_location_title,
                  l10n.privacy_data_location_body,
                ),
                (l10n.privacy_data_selfie_title, l10n.privacy_data_selfie_body),
                (l10n.privacy_data_gender_title, l10n.privacy_data_gender_body),
                (l10n.privacy_data_intent_title, l10n.privacy_data_intent_body),
                (l10n.privacy_data_stay_title, l10n.privacy_data_stay_body),
                (
                  l10n.privacy_data_requests_title,
                  l10n.privacy_data_requests_body,
                ),
                (l10n.privacy_data_chat_title, l10n.privacy_data_chat_body),
                (l10n.privacy_data_blocks_title, l10n.privacy_data_blocks_body),
                (l10n.privacy_data_ip_title, l10n.privacy_data_ip_body),
                (
                  l10n.privacy_data_purchase_title,
                  l10n.privacy_data_purchase_body,
                ),
                (l10n.privacy_data_device_title, l10n.privacy_data_device_body),
              ],
              trailing: [
                l10n.privacy_face_check_body,
                l10n.privacy_profile_on_phone_body,
              ],
            ),
            _Section(
              key: const ValueKey('privacy_bases'),
              icon: Icons.balance_outlined,
              title: l10n.privacy_bases_title,
              bullets: [
                l10n.privacy_basis_contract,
                l10n.privacy_basis_consent,
                l10n.privacy_basis_legitimate,
              ],
            ),
            _Section(
              key: const ValueKey('privacy_retention'),
              icon: Icons.schedule_outlined,
              title: l10n.privacy_retention_title,
              bullets: [
                l10n.privacy_retention_server,
                l10n.privacy_retention_moderation,
                l10n.privacy_retention_purchases,
                l10n.privacy_retention_ip(
                  PrivacyPolicyInfo.hostingLogRetention,
                ),
                l10n.privacy_retention_phone,
              ],
            ),
            _Section(
              key: const ValueKey('privacy_moderation'),
              icon: Icons.flag_outlined,
              title: l10n.privacy_moderation_title,
              paragraphs: [l10n.privacy_moderation_body(SafetyContact.email)],
            ),
            _Section(
              key: const ValueKey('privacy_sharing'),
              icon: Icons.share_outlined,
              title: l10n.privacy_sharing_title,
              bullets: [
                l10n.privacy_sharing_users,
                l10n.privacy_sharing_hosting(PrivacyPolicyInfo.hostingProvider),
                l10n.privacy_sharing_apple_google(
                  PrivacyPolicyInfo.transferSafeguards,
                ),
                l10n.privacy_sharing_authorities,
              ],
            ),
            _Section(
              key: const ValueKey('privacy_rights'),
              icon: Icons.how_to_reg_outlined,
              title: l10n.privacy_rights_title,
              paragraphs: [l10n.privacy_rights_intro],
              bullets: [
                l10n.privacy_rights_profile,
                l10n.privacy_rights_server,
                l10n.privacy_rights_withdraw,
                l10n.privacy_rights_phone,
              ],
              trailing: [
                l10n.privacy_rights_no_copy(SafetyContact.email),
                l10n.privacy_rights_complaint,
              ],
            ),
            _Section(
              key: const ValueKey('privacy_age'),
              icon: Icons.eighteen_up_rating_outlined,
              title: l10n.privacy_age_title,
              paragraphs: [l10n.privacy_age_body],
            ),
            _Section(
              key: const ValueKey('privacy_security'),
              icon: Icons.lock_outline,
              title: l10n.privacy_security_title,
              paragraphs: [l10n.privacy_security_body],
            ),
            _Section(
              key: const ValueKey('privacy_changes'),
              icon: Icons.update_outlined,
              title: l10n.privacy_changes_title,
              paragraphs: [l10n.privacy_changes_body],
            ),
          ],
        ),
      ),
    );
  }
}

/// Una sezione dell'informativa: titolo (intestazione per lo screen reader),
/// poi nell'ordine paragrafi, voci titolo + testo, elenco puntato e
/// paragrafi finali.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    this.paragraphs = const [],
    this.items = const [],
    this.bullets = const [],
    this.trailing = const [],
    super.key,
  });

  final IconData icon;
  final String title;
  final List<String> paragraphs;
  final List<(String, String)> items;
  final List<String> bullets;
  final List<String> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;

    Widget paragraph(String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: body),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ),
            ],
          ),
          for (final text in paragraphs) paragraph(text),
          for (final (itemTitle, itemBody) in items)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(itemTitle, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(itemBody, style: body),
                ],
              ),
            ),
          for (final text in bullets)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: Text('•  ', style: body)),
                  Expanded(child: Text(text, style: body)),
                ],
              ),
            ),
          for (final text in trailing) paragraph(text),
        ],
      ),
    );
  }
}
