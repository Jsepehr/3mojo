import 'package:flutter/material.dart';

/// Errore breve dentro una pagina (sotto un campo, sopra un bottone), al
/// posto del testo rosso nudo: icona + testo su `errorContainer`, angoli
/// arrotondati come le card. È il fratello piccolo di `CmpStatusMessage`
/// (tono `error`), per quando il resto della pagina deve restare visibile.
///
/// Annunciato dai lettori di schermo appena compare (`liveRegion`).
class CmpInlineError extends StatelessWidget {
  const CmpInlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                size: 20,
                color: colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
