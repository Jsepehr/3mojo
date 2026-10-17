import 'dart:ui';

import 'package:flutter/material.dart';

import '/core/theme/raen_colors.dart';
import '/core/utils/photo_data_uri.dart';
import '/core/widgets/cmp_photo.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/l10n/generated/app_localizations.dart';

/// Riga della lista "Vicinanze": nessun nome (l'app non lo chiede) e nessuna
/// distanza (resta un dato interno per l'ordinamento/il paywall, non per
/// l'utente) — solo una foto grande e lo stadio di probabilità d'incontro
/// (Bassa/Media/Alta, come chip colorato) — niente barra di caricamento, dato che
/// sono solo tre stadi discreti, non un valore continuo.
/// `isLocked` (paywall, `features/paywall/`) sfoca solo la foto — la
/// probabilità resta visibile anche bloccata, è proprio quel poco di
/// informazione a dare un motivo per sbloccare la foto vera.
class CmpNearbyPersonTile extends StatelessWidget {
  const CmpNearbyPersonTile({
    super.key,
    required this.person,
    this.isLocked = false,
  });

  final NearbyPerson person;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final photo = imageProviderForPhoto(person.photoUrl);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _Photo(photo: photo, isLocked: isLocked),
            const SizedBox(width: 16),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _MeetingChanceChip(
                  chance: person.meetingChance,
                  label: _meetingChanceLabel(l10n, person.meetingChance),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _meetingChanceLabel(AppLocalizations l10n, MeetingChance chance) {
    switch (chance) {
      case MeetingChance.low:
        return l10n.low_chance_to_meet;
      case MeetingChance.medium:
        return l10n.medium_chance_to_meet;
      case MeetingChance.high:
        return l10n.high_chance_to_meet;
    }
  }
}

/// Stadio di probabilità come chip, tutto nella scala del blu tranne "alta":
/// bassa neutra, media blu tenue col cuore vuoto, alta rosso-cuore col cuore
/// pieno. Il rosso qui significa "buona notizia", mai "male" — per quello
/// c'è `colorScheme.error`.
class _MeetingChanceChip extends StatelessWidget {
  const _MeetingChanceChip({required this.chance, required this.label});

  final MeetingChance chance;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final raen = RaenColors.of(context);

    final (background, foreground, icon, iconColor) = switch (chance) {
      MeetingChance.low => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
        null,
        null,
      ),
      MeetingChance.medium => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        Icons.favorite_border,
        colorScheme.onPrimaryContainer,
      ),
      MeetingChance.high => (
        raen.heartContainer,
        raen.onHeartContainer,
        Icons.favorite,
        raen.heart,
      ),
    };

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: iconColor),
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

/// Foto della tile, sfocata con un lucchetto sopra quando bloccata dal
/// paywall — la stessa `CmpPhoto` di sempre, solo con un filtro applicato.
class _Photo extends StatelessWidget {
  const _Photo({required this.photo, required this.isLocked});

  final ImageProvider? photo;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    final image = CmpPhoto(image: photo, size: 96);
    if (!isLocked) return image;

    final raen = RaenColors.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: image,
        ),
        Icon(
          Icons.lock,
          color: raen.onPhoto,
          size: 28,
          shadows: [Shadow(color: raen.photoScrim, blurRadius: 6)],
        ),
      ],
    );
  }
}
