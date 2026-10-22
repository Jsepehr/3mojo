import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/report_reason.dart';
import '../safety_labels.dart';

/// Chiede il motivo della segnalazione (lista chiusa, niente testo libero)
/// e dice prima di confermare che segnalare **blocca** anche la persona e
/// cosa può succedere dopo. Il motivo scelto, o `null` se annullato.
Future<ReportReason?> showReportDialog(BuildContext context) =>
    showDialog<ReportReason>(
      context: context,
      builder: (_) => const CmpReportDialog(),
    );

class CmpReportDialog extends StatefulWidget {
  const CmpReportDialog({super.key});

  @override
  State<CmpReportDialog> createState() => _CmpReportDialogState();
}

class _CmpReportDialogState extends State<CmpReportDialog> {
  ReportReason? _reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final reason = _reason;

    return AlertDialog(
      icon: const Icon(Icons.flag_outlined),
      title: Text(l10n.report_dialog_title),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l10n.report_dialog_body,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<ReportReason>(
              groupValue: reason,
              onChanged: (selected) => setState(() => _reason = selected),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final value in ReportReason.values)
                    RadioListTile<ReportReason>(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      title: Text(SafetyLabels.reason(l10n, value)),
                      value: value,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: reason == null
              ? null
              : () => Navigator.of(context).pop(reason),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: Text(l10n.report_send),
        ),
      ],
    );
  }
}
