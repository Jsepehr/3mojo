import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/core/errors/failures.dart';
import '/l10n/generated/app_localizations.dart';
import 'providers/pro_demo.dart';

/// Apre la demo dichiarata (`ProDemo.enter`) dal mondo reale — dal drawer,
/// dalla home offline o dal profilo da compilare. Se non si può (es. una
/// sessione reale in corso) lo dice con una snackbar, testo scelto dal tipo
/// di errore ([demoFailureText]).
Future<void> enterDemo(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failure = await context.read<ProDemo>().enter();
  if (failure == null) {
    // Nessun avviso del mondo vero sopra la demo.
    messenger?.clearSnackBars();
    return;
  }
  messenger?.showSnackBar(
    SnackBar(content: Text(demoFailureText(l10n, failure))),
  );
}

/// Il testo tradotto per un errore della demo, dal suo tipo (mai
/// `failure.message`).
String demoFailureText(AppLocalizations l10n, Failure failure) =>
    switch (failure) {
      DemoUnavailableDuringSessionFailure() => l10n.demo_unavailable_online,
      _ => l10n.action_failed_generic,
    };
