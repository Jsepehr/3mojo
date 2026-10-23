import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../providers/pro_paywall.dart';

/// "Sblocco scaduto": una snackbar gentile, **una volta** per sblocco, quando
/// `ProPaywall.expirations` dice che è finito (il chip sparisce e torna il
/// banner d'acquisto da soli). Sta in cima all'app (`app.dart`), come gli
/// altri avvisi una tantum.
///
/// Racconta anche gli sblocchi arrivati **fuori** dalla finestra d'acquisto
/// (`ProPaywall.notices`: pagamento in attesa confermato, acquisto rimasto
/// in sospeso riscattato) — "Sbloccato per le prossime 2 ore" — e un
/// pagamento ricevuto ma non ancora confermato dal server.
class CmpUnlockExpiredListener extends StatefulWidget {
  const CmpUnlockExpiredListener({super.key, required this.child});

  final Widget child;

  @override
  State<CmpUnlockExpiredListener> createState() =>
      _CmpUnlockExpiredListenerState();
}

class _CmpUnlockExpiredListenerState extends State<CmpUnlockExpiredListener> {
  StreamSubscription<void>? _subscription;
  StreamSubscription<PaywallNotice>? _noticeSubscription;

  @override
  void initState() {
    super.initState();
    final proPaywall = context.read<ProPaywall>();
    _subscription = proPaywall.expirations.listen(
      (_) => _show((l10n) => l10n.unlock_expired),
    );
    _noticeSubscription = proPaywall.notices.listen(
      (notice) => _show(
        (l10n) => switch (notice) {
          PaywallNotice.unlocked => l10n.unlocked_for_the_next_2_hours,
          PaywallNotice.deliveryDelayed => l10n.unlock_delivery_delayed,
        },
      ),
    );
  }

  void _show(String Function(AppLocalizations l10n) text) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text(l10n))));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _noticeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
