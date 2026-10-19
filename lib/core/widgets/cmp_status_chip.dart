import 'package:flutter/material.dart';

/// Etichetta di stato a pillola, non cliccabile: icona facoltativa + testo
/// `labelLarge`. Una sola forma per tutti gli stati brevi dell'app
/// (probabilità d'incontro, "Richiesta inviata", stato di una richiesta):
/// cambiano solo i colori, che sceglie chi la usa dal tema o da
/// `RaenColors` — qui nessun colore è deciso.
///
/// Con [outlined] il fondo è trasparente e c'è un bordo ([borderColor], di
/// default `outline`): neutro per gli stati "chiusi" (rifiutata, finita),
/// che non devono attirare l'occhio, oppure colorato per distinguersi dai
/// chip pieni accanto.
class CmpStatusChip extends StatelessWidget {
  const CmpStatusChip({
    super.key,
    required this.label,
    required this.foreground,
    this.background,
    this.icon,
    this.iconColor,
    this.outlined = false,
    this.borderColor,
  });

  final String label;
  final Color foreground;
  final Color? background;
  final IconData? icon;
  final Color? iconColor;
  final bool outlined;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: outlined ? null : background,
        shape: StadiumBorder(
          side: outlined
              ? BorderSide(color: borderColor ?? theme.colorScheme.outline)
              : BorderSide.none,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: iconColor ?? foreground),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
