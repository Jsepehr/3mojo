import 'package:flutter/material.dart';

/// Foto quadrata con angoli arrotondati (raggio 20) — mai un cerchio, usata
/// sia per il selfie del profilo che per le foto delle altre persone, per
/// uno stile visivo coerente in tutta l'app. Mostra un'icona segnaposto
/// quando non c'è ancora nessuna immagine.
class CmpPhoto extends StatelessWidget {
  const CmpPhoto({
    super.key,
    required this.image,
    required this.size,
    this.placeholderIcon = Icons.person,
  });

  final ImageProvider? image;
  final double size;
  final IconData placeholderIcon;

  static const double cornerRadius = 20;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: Container(
        width: size,
        height: size,
        color: colorScheme.surfaceContainerHighest,
        child: image == null
            ? Icon(
                placeholderIcon,
                size: size * 0.4,
                color: colorScheme.onSurfaceVariant,
              )
            : Image(image: image!, fit: BoxFit.cover),
      ),
    );
  }
}
