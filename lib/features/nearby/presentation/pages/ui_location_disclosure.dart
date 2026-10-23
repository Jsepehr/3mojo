import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/location_disclosure.dart';
import '../providers/pro_nearby.dart';

/// Prima di andare online, se serve: l'avviso in evidenza sulla posizione,
/// poi la richiesta di sistema. `true` se lo Start può partire (permesso
/// concesso, già prima o adesso); `false` con "Non ora" (si resta offline,
/// nessuna richiesta di sistema) o se il permesso non viene concesso (si
/// resta offline e un avviso porta alle impostazioni).
///
/// Quando mostrarlo lo decide `GetLocationDisclosureUseCase` (finché il
/// permesso non è concesso); che senza permesso non si va online,
/// `RequestLocationPermissionUseCase`. Qui solo la sequenza a schermo.
Future<bool> showLocationDisclosureIfNeeded(BuildContext context) async {
  final proNearby = context.read<ProNearby>();
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final l10n = AppLocalizations.of(context)!;

  final disclosure = await proNearby.locationDisclosureToShow();
  if (disclosure == null) return true;
  if (!navigator.mounted) return false;

  final accepted = await navigator.push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => UiLocationDisclosure(disclosure: disclosure),
    ),
  );
  if (accepted != true) return false;

  if (await proNearby.requestLocationPermission()) return true;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.location_permission_needed_to_go_online),
        action: SnackBarAction(
          label: l10n.open_settings,
          onPressed: proNearby.openAppSettings,
        ),
      ),
    );
  return false;
}

/// L'avviso in evidenza sulla posizione (politica "Dati utente" di Google
/// Play, "prominent disclosure"), a schermo intero e staccato da
/// informativa e termini: a cosa serve la posizione, che da online continua
/// a essere usata anche in background **solo dove è vero**
/// ([LocationDisclosure.continuesInBackground]: Android con la notifica
/// fissa; su iOS solo con l'app aperta sullo schermo), che da offline non si
/// usa e non si conserva. "Continua" (`true`) porta alla richiesta di
/// sistema; "Non ora" o indietro (`false`/`null`) lasciano offline.
class UiLocationDisclosure extends StatelessWidget {
  const UiLocationDisclosure({required this.disclosure, super.key});

  final LocationDisclosure disclosure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: theme.colorScheme.primary)),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          Icons.location_on_rounded,
                          size: 56,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.location_disclosure_title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      point(Icons.people_outline, l10n.location_disclosure_use),
                      if (disclosure.continuesInBackground)
                        point(
                          Icons.notifications_active_outlined,
                          l10n.location_disclosure_background,
                        )
                      else
                        point(
                          Icons.phone_iphone_outlined,
                          l10n.location_disclosure_foreground_only,
                        ),
                      point(
                        Icons.location_off_outlined,
                        l10n.location_disclosure_offline,
                      ),
                      point(
                        Icons.verified_user_outlined,
                        l10n.location_disclosure_next_step,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.location_disclosure_continue),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.location_disclosure_not_now),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
