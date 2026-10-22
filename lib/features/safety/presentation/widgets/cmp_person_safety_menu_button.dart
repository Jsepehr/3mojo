import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../providers/pro_safety.dart';
import '../safety_labels.dart';
import 'cmp_block_confirm_dialog.dart';
import 'cmp_report_dialog.dart';

/// Cosa si sceglie dal menu "⋯" di una persona.
enum _SafetyChoice { report, block }

/// Il bottone "⋯" con **Segnala** e **Blocca** per una persona di questa
/// sessione ([personId] = il suo pseudonimo): sulle tile di "Vicinanze",
/// sulle richieste in entrata e in uscita e nell'AppBar del match. Un vero
/// bottone (non un long-press nascosto): si trova a colpo d'occhio, ha un
/// tooltip che fa da etichetta per lo screen reader e un'area di tocco di
/// 48 dp.
///
/// Ogni scelta passa da una conferma (dialog), poi da `ProSafety`; l'esito
/// è una snackbar, con una vibrazione decisa (come End) quando parte. La
/// snackbar usa lo `ScaffoldMessenger` preso **prima** delle attese: se la
/// persona era il tuo match, la sua pagina si chiude da sola appena la
/// blocchi.
class CmpPersonSafetyMenuButton extends StatelessWidget {
  const CmpPersonSafetyMenuButton({
    super.key,
    required this.personId,
    this.color,
  });

  final String personId;

  /// Colore dell'icona (es. sopra una foto); di default quello del tema.
  final Color? color;

  Future<void> _onSelected(BuildContext context, _SafetyChoice choice) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final proSafety = context.read<ProSafety>();

    void show(String text) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }

    switch (choice) {
      case _SafetyChoice.block:
        if (!await showBlockConfirmDialog(context)) return;
        HapticFeedback.mediumImpact();
        proSafety
            .block(personId)
            .match(
              (failure) => show(SafetyLabels.failure(l10n, failure)),
              (_) => show(l10n.person_blocked),
            );
      case _SafetyChoice.report:
        final reason = await showReportDialog(context);
        if (reason == null) return;
        HapticFeedback.mediumImpact();
        proSafety
            .report(personId, reason)
            .match(
              (failure) => show(SafetyLabels.failure(l10n, failure)),
              (_) => show(l10n.person_reported),
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final errorColor = Theme.of(context).colorScheme.error;

    return PopupMenuButton<_SafetyChoice>(
      tooltip: l10n.safety_menu_tooltip,
      icon: Icon(Icons.more_vert, color: color),
      onSelected: (choice) => _onSelected(context, choice),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _SafetyChoice.report,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.flag_outlined),
            title: Text(l10n.report),
          ),
        ),
        PopupMenuItem(
          value: _SafetyChoice.block,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.block, color: errorColor),
            title: Text(l10n.block, style: TextStyle(color: errorColor)),
          ),
        ),
      ],
    );
  }
}
