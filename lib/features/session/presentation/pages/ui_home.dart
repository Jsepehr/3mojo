import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/features/encounters/presentation/pages/ui_encounters.dart';
import '/features/encounters/presentation/providers/pro_encounters.dart';
import '/features/nearby/presentation/widgets/cmp_nearby_list.dart';
import '/features/session/presentation/providers/pro_session.dart';
import '/features/session/presentation/widgets/cmp_radar_background.dart';
import '/l10n/generated/app_localizations.dart';
import 'ui_start_session.dart';

/// Pagina iniziale dell'app: un'unica pagina che cambia aspetto in base a
/// `ProSession.isOnline`, non due pagine separate.
class UiHome extends StatelessWidget {
  const UiHome({super.key});

  @override
  Widget build(BuildContext context) {
    final proSession = context.watch<ProSession>();

    if (proSession.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return proSession.isOnline ? const _OnlineHome() : const _OfflineHome();
  }
}

/// Stato offline: claim + bottone Start, sfondo radar decorativo.
class _OfflineHome extends StatelessWidget {
  const _OfflineHome();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: CmpRadarBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.homeTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.homeSubtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UiStartSession()),
                    ),
                    child: Text(l10n.homeStartButton),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stato online: un'unica pagina — AppBar con bottone End (rosso), body con
/// la lista delle persone vicine, e bottom app bar con la tua foto profilo
/// (piccola, solo a titolo di conferma "sei online con questa foto") e
/// l'icona "Richieste" con badge sulle richieste in attesa.
class _OnlineHome extends StatelessWidget {
  const _OnlineHome();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = context.watch<ProSession>().session!;
    final pendingCount = context.watch<ProEncounters>().pendingIncomingCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.nearbyPageTitle),
        actions: [
          TextButton(
            onPressed: () => context.read<ProSession>().end(),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.homeEndButton),
          ),
        ],
      ),
      body: const CmpNearbyList(),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: FileImage(File(session.selfiePath)),
            ),
            IconButton.filledTonal(
              icon: pendingCount == 0
                  ? const Icon(Icons.favorite_border)
                  : Badge(
                      label: Text('$pendingCount'),
                      child: const Icon(Icons.favorite_border),
                    ),
              tooltip: l10n.encountersPageTitle,
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const UiEncounters())),
            ),
          ],
        ),
      ),
    );
  }
}
