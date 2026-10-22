import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';
import 'cmp_terms_of_use.dart';

/// Chiede di accettare i termini d'uso a chi ha un profilo salvato prima
/// che esistessero (lo Start lo rifiuta con `TermsNotAcceptedFailure`):
/// il testo intero e una casella da spuntare prima di "Accetto". `true`
/// solo se accettati — a salvarli ci pensa chi chiama (`ProProfile`).
Future<bool> showTermsAcceptanceDialog(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (_) => const CmpTermsAcceptanceDialog(),
  );
  return accepted ?? false;
}

class CmpTermsAcceptanceDialog extends StatefulWidget {
  const CmpTermsAcceptanceDialog({super.key});

  @override
  State<CmpTermsAcceptanceDialog> createState() =>
      _CmpTermsAcceptanceDialogState();
}

class _CmpTermsAcceptanceDialogState extends State<CmpTermsAcceptanceDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.terms_of_use),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.terms_accept_dialog_body),
            const SizedBox(height: 16),
            const CmpTermsOfUse(),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.terms_accept_checkbox),
              value: _checked,
              onChanged: (value) => setState(() => _checked = value ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _checked ? () => Navigator.of(context).pop(true) : null,
          child: Text(l10n.accept),
        ),
      ],
    );
  }
}
