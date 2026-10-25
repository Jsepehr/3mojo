import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';

/// Pillola "Demo" accanto a ogni persona dimostrativa (tile di "Vicinanze",
/// richieste, chat): nella demo dichiarata nessuna persona deve poter
/// sembrare reale, nemmeno a colpo d'occhio. Lo screen reader legge
/// "Persona dimostrativa". Chi la usa la mostra solo dentro la demo
/// (`DemoMode.isActive`). Colori "invertiti" (`inverseSurface`), come il
/// banner della demo: diversi da ogni chip di stato dell'app.
class CmpDemoBadge extends StatelessWidget {
  const CmpDemoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      label: l10n.demo_person_semantics,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colorScheme.inverseSurface,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 14,
                color: colorScheme.onInverseSurface,
              ),
              const SizedBox(width: 4),
              Text(
                l10n.demo_badge,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onInverseSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
