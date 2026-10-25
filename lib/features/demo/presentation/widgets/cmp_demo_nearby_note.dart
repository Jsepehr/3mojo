import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';

/// Una riga in cima a "Vicinanze" nella demo dichiarata: la lista della
/// demo è piena da subito, ma nella realtà compare solo chi resta fermo
/// vicino a te da almeno un minuto (regola del server) — lo si dice invece
/// di farlo aspettare.
class CmpDemoNearbyNote extends StatelessWidget {
  const CmpDemoNearbyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.demo_nearby_note,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
