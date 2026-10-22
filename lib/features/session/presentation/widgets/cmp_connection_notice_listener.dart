import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../providers/pro_connection.dart';

/// Mostra un avviso (snackbar) quando la sessione è ripartita da zero lato
/// server dopo una caduta troppo lunga: richieste e chat di prima non ci
/// sono più. E un dialogo quando il server ha **chiuso** la sessione dopo
/// le segnalazioni di più persone (End lo fa già `ProSession`): una cosa
/// così non deve sparire in pochi secondi. Sta in cima all'app
/// (`app.dart`), sopra ogni pagina.
class CmpConnectionNoticeListener extends StatefulWidget {
  const CmpConnectionNoticeListener({super.key, required this.child});

  final Widget child;

  @override
  State<CmpConnectionNoticeListener> createState() =>
      _CmpConnectionNoticeListenerState();
}

class _CmpConnectionNoticeListenerState
    extends State<CmpConnectionNoticeListener> {
  StreamSubscription<void>? _subscription;
  StreamSubscription<void>? _closureSubscription;

  @override
  void initState() {
    super.initState();
    _subscription = context.read<ProConnection>().restarts.listen((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(l10n.session_restarted)));
    });
    _closureSubscription = context.read<ProConnection>().closures.listen((_) {
      if (!mounted) return;
      final navigator = Navigator.maybeOf(context, rootNavigator: true);
      if (navigator == null) return;
      final l10n = AppLocalizations.of(context)!;
      showDialog<void>(
        context: navigator.context,
        builder: (context) => AlertDialog(
          title: Text(l10n.session_closed_after_reports_title),
          content: Text(l10n.session_closed_after_reports_body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _closureSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
