import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';
import '../widgets/cmp_terms_of_use.dart';

/// I termini d'uso da leggere con calma: dal profilo ("Leggi i termini") e
/// da "Sicurezza e segnalazioni".
class UiTermsOfUse extends StatelessWidget {
  const UiTermsOfUse({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.terms_of_use)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: const [CmpTermsOfUse()],
        ),
      ),
    );
  }
}
