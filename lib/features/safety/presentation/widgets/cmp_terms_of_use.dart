import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';

/// Il testo dei termini d'uso (versione `Profile.currentTermsVersion`):
/// brevi, una regola per riga, con **tolleranza zero** per i contenuti
/// inaccettabili e le conseguenze delle segnalazioni scritte chiaramente
/// (chiusura della sessione, record di moderazione conservato 30 giorni).
/// Lo stesso widget sta nella pagina dei termini (`UiTermsOfUse`) e nel
/// dialog di accettazione allo Start: un solo testo da tenere allineato.
/// Cambiarlo nella sostanza vuol dire alzare `Profile.currentTermsVersion`.
class CmpTermsOfUse extends StatelessWidget {
  const CmpTermsOfUse({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final rules = [
      (Icons.eighteen_up_rating_outlined, l10n.terms_rule_adults),
      (Icons.face_outlined, l10n.terms_rule_own_photo),
      (Icons.do_not_disturb_on_outlined, l10n.terms_rule_no_offensive),
      (Icons.handshake_outlined, l10n.terms_rule_respect),
      (Icons.gavel_outlined, l10n.terms_rule_enforcement),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.terms_intro, style: theme.textTheme.bodyLarge),
        for (final (icon, text) in rules)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(icon, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
