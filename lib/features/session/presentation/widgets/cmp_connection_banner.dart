import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../providers/pro_connection.dart';

/// Striscia discreta "connessione persa, mi sto riconnettendo…" sopra un
/// contenuto che resta visibile (la lista delle persone, la chat): la
/// riconnessione è automatica, non c'è nulla da fare — solo da sapere che
/// per un attimo ciò che si vede potrebbe non essere aggiornato e che le
/// azioni potrebbero non partire. Sparisce da sola appena si è di nuovo
/// collegati.
class CmpConnectionBanner extends StatelessWidget {
  const CmpConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isReconnecting = context.watch<ProConnection>().isReconnecting;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: isReconnecting
          ? const _Strip()
          : const SizedBox(width: double.infinity),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      liveRegion: true,
      child: ColoredBox(
        color: colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.connection_reconnecting,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
