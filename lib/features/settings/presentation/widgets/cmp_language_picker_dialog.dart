import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/features/settings/domain/entities/app_language.dart';
import '/features/settings/presentation/providers/pro_settings.dart';
import '/l10n/generated/app_localizations.dart';

/// Dialog con le lingue disponibili, aperto dalla voce "Change language"
/// del menu laterale. La scelta si applica subito (nessun bottone Conferma).
class CmpLanguagePickerDialog extends StatelessWidget {
  const CmpLanguagePickerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentLanguage = context.watch<ProSettings>().language;

    return SimpleDialog(
      title: Text(l10n.languagePickerTitle),
      children: [
        RadioGroup<AppLanguage>(
          groupValue: currentLanguage,
          onChanged: (selected) {
            if (selected == null) return;
            context.read<ProSettings>().setLanguage(selected);
            Navigator.of(context).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final language in AppLanguage.values)
                RadioListTile<AppLanguage>(
                  title: Text(_labelFor(l10n, language)),
                  value: language,
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _labelFor(AppLocalizations l10n, AppLanguage language) {
    switch (language) {
      case AppLanguage.system:
        return l10n.languageOptionSystem;
      case AppLanguage.english:
        return l10n.languageOptionEnglish;
      case AppLanguage.italian:
        return l10n.languageOptionItalian;
    }
  }
}
