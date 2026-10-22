import 'package:flutter/material.dart';

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
      content: Text(l10n.block_dialog_body),
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
