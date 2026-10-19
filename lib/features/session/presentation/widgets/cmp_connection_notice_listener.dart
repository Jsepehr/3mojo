import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../providers/pro_connection.dart';

/// Mostra un avviso (snackbar) quando la sessione è ripartita da zero lato
/// server dopo una caduta troppo lunga: richieste e chat di prima non ci
/// sono più. Sta in cima all'app (`app.dart`), sopra ogni pagina.
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
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
