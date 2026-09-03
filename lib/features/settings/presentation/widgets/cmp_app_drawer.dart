import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '/features/settings/presentation/providers/pro_settings.dart';
import '/l10n/generated/app_localizations.dart';
import 'cmp_language_picker_dialog.dart';

/// Menu laterale dell'app: cambio lingua, informazioni sull'app,
/// condivisione. Nessuna voce di navigazione qui dentro — è un cassetto di
/// impostazioni, non una seconda barra di navigazione.
class CmpAppDrawer extends StatelessWidget {
  const CmpAppDrawer({super.key});

  Future<void> _changeLanguage(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const CmpLanguagePickerDialog(),
    );
  }

  Future<void> _showAbout(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final packageInfo = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    showAboutDialog(
      context: context,
      applicationName: l10n.appTitle,
      applicationVersion: packageInfo.version,
      children: [Text(l10n.aboutAppDescription)],
    );
  }

  void _shareApp(BuildContext context, AppLocalizations l10n) {
    final box = context.findRenderObject() as RenderBox?;
    SharePlus.instance.share(
      ShareParams(
        text: l10n.shareAppMessage,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDarkMode = context.watch<ProSettings>().isDarkMode;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(l10n.drawerChangeLanguage),
              onTap: () {
                Navigator.of(context).pop();
                _changeLanguage(context);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: Text(l10n.drawerDarkMode),
              value: isDarkMode,
              onChanged: (enabled) =>
                  context.read<ProSettings>().setDarkMode(enabled),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.drawerAbout),
              onTap: () {
                Navigator.of(context).pop();
                _showAbout(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: Text(l10n.drawerShareApp),
              onTap: () {
                Navigator.of(context).pop();
                _shareApp(context, l10n);
              },
            ),
          ],
        ),
      ),
    );
  }
}
