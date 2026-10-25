import 'package:flutter/material.dart';

import '/core/demo/demo_mode.dart';
import '/l10n/generated/app_localizations.dart';

/// Chiede conferma prima di bloccare: cosa succede, e — onestamente — fino
/// a quando (il resto di questa sessione: Raen non ha account). `true` solo
/// se si conferma.
Future<bool> showBlockConfirmDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const CmpBlockConfirmDialog(),
  );
  return confirmed ?? false;
}

class CmpBlockConfirmDialog extends StatelessWidget {
  const CmpBlockConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: const Icon(Icons.block),
      title: Text(l10n.block_dialog_title),
      content: DemoMode.isActive(context)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.block_dialog_body),
                const SizedBox(height: 12),
                _DemoNote(text: l10n.demo_nothing_is_sent),
              ],
            )
          : Text(l10n.block_dialog_body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        // Azione che chiude rapporti: rosso errore, come "Termina".
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          child: Text(l10n.block),
        ),
      ],
    );
  }
}

/// La nota della demo dichiarata sotto la spiegazione del blocco.
class _DemoNote extends StatelessWidget {
  const _DemoNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
