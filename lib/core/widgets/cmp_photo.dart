import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Foto quadrata con angoli arrotondati — mai un cerchio, usata sia per il
/// selfie del profilo che per le foto delle altre persone, per uno stile
/// visivo coerente in tutta l'app. Il raggio è proporzionale al lato
/// ([radiusFor]): la stessa forma a ogni dimensione, dalla miniatura nella
/// barra in basso al selfie grande dello Start. Mostra un'icona segnaposto
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

  /// Raggio degli angoli per una foto di lato [size]: circa un quinto del
  /// lato, mai sotto gli 8 px (sotto non si vede più che è arrotondata).
  /// Chi disegna sopra la foto (velo, bordo) usa lo stesso valore.
  static double radiusFor(double size) => math.max(8, size * 0.21);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radiusFor(size)),
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
            // gaplessPlayback: cambiando foto (nuovo scatto, ribaltamento)
            // resta quella vecchia finché la nuova non è pronta, invece di
            // un lampo del fondo vuoto.
            : Image(image: image!, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}
