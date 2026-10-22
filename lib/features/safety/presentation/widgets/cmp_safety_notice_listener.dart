import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/safety_rejection.dart';
import '../providers/pro_safety.dart';
import '../safety_labels.dart';

/// Mostra una snackbar quando il server rifiuta un blocco o una
/// segnalazione già partiti (la persona era già uscita, troppe
/// segnalazioni…): l'utente non deve credere che sia andata se non è
/// andata. Sta in cima all'app (`app.dart`), sopra ogni pagina.
class CmpSafetyNoticeListener extends StatefulWidget {
  const CmpSafetyNoticeListener({super.key, required this.child});

  final Widget child;

  @override
  State<CmpSafetyNoticeListener> createState() =>
      _CmpSafetyNoticeListenerState();
}

class _CmpSafetyNoticeListenerState extends State<CmpSafetyNoticeListener> {
  StreamSubscription<SafetyRejection>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = context.read<ProSafety>().rejections.listen((rejection) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(SafetyLabels.rejection(l10n, rejection))),
      );
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
