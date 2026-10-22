import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../providers/pro_paywall.dart';

/// "Sblocco scaduto": una snackbar gentile, **una volta** per sblocco, quando
/// `ProPaywall.expirations` dice che è finito (il chip sparisce e torna il
/// banner d'acquisto da soli). Sta in cima all'app (`app.dart`), come gli
/// altri avvisi una tantum.
class CmpUnlockExpiredListener extends StatefulWidget {
  const CmpUnlockExpiredListener({super.key, required this.child});

  final Widget child;

  @override
  State<CmpUnlockExpiredListener> createState() =>
      _CmpUnlockExpiredListenerState();
}

class _CmpUnlockExpiredListenerState extends State<CmpUnlockExpiredListener> {
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = context.read<ProPaywall>().expirations.listen((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(l10n.unlock_expired)));
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
