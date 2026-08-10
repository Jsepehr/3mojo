import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../encounters/presentation/pages/ui_encounters.dart';
import '../../../encounters/presentation/providers/pro_encounters.dart';
import '../../../nearby/presentation/pages/ui_nearby.dart';
import '../providers/pro_session.dart';
import '../widgets/cmp_radar_background.dart';
import 'ui_start_session.dart';

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

class _OnlineHome extends StatelessWidget {
  const _OnlineHome();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = context.watch<ProSession>().session!;
    final pendingCount = context.watch<ProEncounters>().pendingIncomingCount;

    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: () => context.read<ProSession>().end(),
            child: Text(l10n.homeEndButton),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(child: CmpRadarBackground()),
          CircleAvatar(
            radius: 72,
            backgroundImage: FileImage(File(session.selfiePath)),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton.filledTonal(
              icon: const Icon(Icons.list),
              tooltip: l10n.nearbyPageTitle,
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const UiNearby())),
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
