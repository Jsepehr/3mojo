import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';

/// Banner fisso in cima a **tutte** le pagine della demo dichiarata (lo
/// mette `DemoScope` sopra il `Navigator`, quindi resta anche sopra pagine,
/// tendine e dialoghi): "Demo — persone dimostrative, non reali" e il
/// bottone "Esci dalla demo". Colori "invertiti" (`inverseSurface`), come
/// il badge "Demo": non si confonde con nessun'altra striscia dell'app.
///
/// Sta sopra il `Navigator`, quindi niente tooltip né altro che chieda un
/// `Overlay`: ha il suo `Material` per l'effetto del tocco.
class CmpDemoBanner extends StatelessWidget {
  const CmpDemoBanner({
    super.key,
    required this.onExit,
    this.isExiting = false,
  });

  final VoidCallback onExit;

  /// Uscita in corso: il bottone si disattiva (niente doppio tap).
  final bool isExiting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.inverseSurface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final title = Semantics(
                header: true,
                child: Text(
                  l10n.demo_banner_title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onInverseSurface,
                  ),
                ),
              );
              final exit = TextButton(
                onPressed: isExiting ? null : onExit,
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.inversePrimary,
                ),
                child: Text(l10n.demo_exit),
              );
              final icon = Icon(
                Icons.smart_toy_outlined,
                size: 20,
                color: colorScheme.onInverseSurface,
              );
              // Testo grande: il bottone va sotto il titolo, non lo
              // schiaccia.
              if (MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(width: 12),
                          Expanded(child: title),
                        ],
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: exit,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(child: title),
                  const SizedBox(width: 8),
                  exit,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
