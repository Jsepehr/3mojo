import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';
import '../demo_entry.dart';

/// Link discreto "Come funziona? Prova la demo" (sotto Start nella home
/// offline, in fondo al profilo da compilare): apre la demo dichiarata.
/// Prende i colori dal tema in cui sta (bianco nel tema hero della home).
class CmpTryDemoLink extends StatelessWidget {
  const CmpTryDemoLink({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return TextButton.icon(
      onPressed: () => enterDemo(context),
      icon: const Icon(Icons.play_circle_outline),
      label: Text(l10n.demo_try_link),
    );
  }
}
