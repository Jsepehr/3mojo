import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '/features/profile/presentation/pages/ui_profile.dart';
import '/features/safety/presentation/pages/ui_privacy_policy.dart';
import '/features/safety/presentation/pages/ui_safety.dart';
import '/features/safety/presentation/pages/ui_terms_of_use.dart';
import '/features/settings/presentation/providers/pro_settings.dart';
import '/l10n/generated/app_localizations.dart';
import 'cmp_language_picker_dialog.dart';

/// Menu laterale dell'app: il proprio profilo, cambio lingua, tema,
/// "Sicurezza e segnalazioni" (come bloccare/segnalare, termini d'uso e il
/// contatto pubblicato), l'informativa privacy, informazioni sull'app,
/// condivisione. Nessuna altra voce di navigazione
/// qui dentro — è un cassetto di impostazioni, non una seconda barra di
/// navigazione.
///
/// In fondo, separata, la voce per sviluppatori "dati finti": esiste solo
/// nei build in cui la modalità finta è disponibile
/// (`ProSettings.isFakeModeAvailable`, i build di debug).
///
/// Ogni voce che chiude il drawer e poi apre qualcosa cattura **prima** il
/// `Navigator` (e i testi): dopo `pop()` il `context` del drawer non è più
/// montato e non va più usato.
class CmpAppDrawer extends StatelessWidget {
  const CmpAppDrawer({super.key});

  void _openProfile(BuildContext context) {
    Navigator.of(context)
      ..pop()
      ..push(MaterialPageRoute(builder: (_) => const UiProfile()));
  }

  void _openSafety(BuildContext context) {
    Navigator.of(context)
      ..pop()
      ..push(MaterialPageRoute(builder: (_) => const UiSafety()));
  }

  void _openPrivacyPolicy(BuildContext context) {
    Navigator.of(context)
      ..pop()
      ..push(MaterialPageRoute(builder: (_) => const UiPrivacyPolicy()));
  }

  void _changeLanguage(BuildContext context) {
    final navigator = Navigator.of(context)..pop();
    showDialog<void>(
      context: navigator.context,
      builder: (_) => const CmpLanguagePickerDialog(),
    );
  }

  /// "Informazioni": versione, copyright (anno corrente), i link a termini
  /// d'uso, informativa privacy e sicurezza, e il bottone "Licenze" di Flutter (pacchetti Dart più
  /// ciò che aggiunge `registerAppLicenses`: font e librerie native). Le
  /// pagine si aprono **sopra** il dialog: tornando indietro si ritrova.
  Future<void> _showAbout(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context)..pop();
    final packageInfo = await PackageInfo.fromPlatform();
    if (!navigator.mounted) return;

    showAboutDialog(
      context: navigator.context,
      applicationName: l10n.app_title,
      applicationVersion: packageInfo.version,
      applicationLegalese: l10n.about_legalese('${DateTime.now().year}'),
      children: [
        Text(l10n.meet_people_nearby_in_real_time),
        const SizedBox(height: 8),
        _AboutLink(
          icon: Icons.description_outlined,
          label: l10n.terms_of_use,
          page: const UiTermsOfUse(),
        ),
        _AboutLink(
          icon: Icons.privacy_tip_outlined,
          label: l10n.privacy_policy,
          page: const UiPrivacyPolicy(),
        ),
        _AboutLink(
          icon: Icons.shield_outlined,
          label: l10n.safety_and_reports,
          page: const UiSafety(),
        ),
      ],
    );
  }

  void _shareApp(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Posizione del popover (iPad): letta finché il drawer è ancora a
    // schermo.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    Navigator.of(context).pop();
    SharePlus.instance.share(
      ShareParams(
        text: l10n.check_out_raen_an_app_to_meet_people_nearby_in_real_time,
        sharePositionOrigin: origin,
      ),
    );
  }

  void _toggleFakeMode(BuildContext context, bool enabled) {
    final l10n = AppLocalizations.of(context)!;
    context.read<ProSettings>().setFakeMode(enabled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.restart_the_app_to_apply_this_change)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final proSettings = context.watch<ProSettings>();

    return Drawer(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(color: theme.colorScheme.primary),
                  child: Align(
                    alignment: AlignmentDirectional.bottomStart,
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 40,
                          color: theme.colorScheme.onPrimary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          l10n.app_title,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(l10n.my_profile),
                  onTap: () => _openProfile(context),
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(l10n.change_language),
                  onTap: () => _changeLanguage(context),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: Text(l10n.dark_mode),
                  value: proSettings.isDarkMode,
                  onChanged: (enabled) =>
                      context.read<ProSettings>().setDarkMode(enabled),
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(l10n.safety_and_reports),
                  onTap: () => _openSafety(context),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(l10n.privacy_policy),
                  onTap: () => _openPrivacyPolicy(context),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.about),
                  onTap: () => _showAbout(context),
                ),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: Text(l10n.share_app),
                  onTap: () => _shareApp(context),
                ),
              ],
            ),
          ),
          if (proSettings.isFakeModeAvailable)
            SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      12,
                      16,
                      0,
                    ),
                    child: Text(
                      l10n.developer_options,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.wifi_off_outlined),
                    title: Text(l10n.fake_data_no_network),
                    value: proSettings.isFakeMode,
                    onChanged: (enabled) => _toggleFakeMode(context, enabled),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Una voce del dialog "Informazioni" che apre una pagina sopra il dialog.
class _AboutLink extends StatelessWidget {
  const _AboutLink({
    required this.icon,
    required this.label,
    required this.page,
  });

  final IconData icon;
  final String label;
  final Widget page;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(label),
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page)),
  );
}
