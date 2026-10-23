import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';

/// Chiede di riconfermare il consenso al dato sensibile a chi l'aveva dato
/// per una versione precedente del testo (lo Start lo rifiuta con
/// `SensitiveDataConsentRequiredFailure`, vedi
/// `Profile.currentSensitiveConsentVersion`): il testo attuale come casella
/// da spuntare prima di "Accetto", e la via d'uscita senza consenso
/// (percorso neutro nel profilo). `true` solo se riconfermato — a salvarlo
/// ci pensa chi chiama (`ProProfile.renewSensitiveConsent`).
Future<bool> showSensitiveConsentRenewalDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const CmpSensitiveConsentRenewalDialog(),
  );
  return confirmed ?? false;
}

class CmpSensitiveConsentRenewalDialog extends StatefulWidget {
  const CmpSensitiveConsentRenewalDialog({super.key});

  @override
  State<CmpSensitiveConsentRenewalDialog> createState() =>
      _CmpSensitiveConsentRenewalDialogState();
}

class _CmpSensitiveConsentRenewalDialogState
    extends State<CmpSensitiveConsentRenewalDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.consent_renewal_title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.consent_renewal_body),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                l10n.i_agree_that_raen_uses_my_gender_and_who_i_want_to_meet,
              ),
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
