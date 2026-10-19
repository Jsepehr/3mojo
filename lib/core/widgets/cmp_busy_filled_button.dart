import 'package:flutter/material.dart';

import 'cmp_loading_indicator.dart';

/// `FilledButton` principale di una pagina con uno stato "ci sto lavorando"
/// ([isBusy]): non accetta tap e mostra i puntini al posto del testo,
/// **restando nel colore pieno** — un `FilledButton` disattivato di Material
/// diventa grigio chiarissimo, e i puntini `onPrimary` sopra spariscono.
///
/// Con [onPressed] `null` (e non busy) è un normale bottone disattivato.
class CmpBusyFilledButton extends StatelessWidget {
  const CmpBusyFilledButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isBusy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilledButton(
      onPressed: isBusy ? null : onPressed,
      style: isBusy
          ? FilledButton.styleFrom(
              disabledBackgroundColor: colorScheme.primary,
              disabledForegroundColor: colorScheme.onPrimary,
            )
          : null,
      child: isBusy
          ? Semantics(
              label: label,
              child: CmpLoadingIndicator(
                size: 20,
                color: colorScheme.onPrimary,
              ),
            )
          : Text(label),
    );
  }
}
