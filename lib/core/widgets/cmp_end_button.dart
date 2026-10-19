import 'package:flutter/material.dart';

import 'cmp_loading_indicator.dart';

/// Il bottone "End" dell'AppBar, uguale ovunque si esca da qualcosa (la
/// sessione in "Vicinanze", l'incontro nella chat): rosso errore del tema,
/// la stessa icona, cambia solo il testo ([label]).
///
/// Con [isBusy] (uscita già in corso) non accetta altri tap e mostra i
/// puntini al posto dell'icona, restando rosso: "ci sto lavorando", non
/// "non si può".
class CmpEndButton extends StatelessWidget {
  const CmpEndButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isBusy = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isBusy;

  static const IconData icon = Icons.stop_circle_outlined;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;

    return TextButton.icon(
      onPressed: isBusy ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: error,
        disabledForegroundColor: error,
        iconColor: error,
        disabledIconColor: error,
      ),
      icon: isBusy
          ? CmpLoadingIndicator(size: 20, color: error)
          : const Icon(icon),
      label: Text(label),
    );
  }
}
