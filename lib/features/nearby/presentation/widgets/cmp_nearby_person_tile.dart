import 'dart:ui';

import 'package:flutter/material.dart';

import '/core/utils/photo_data_uri.dart';
import '/core/widgets/cmp_photo.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/l10n/generated/app_localizations.dart';

/// Riga della lista "Vicinanze": nessun nome (l'app non lo chiede), solo
/// una foto grande, la distanza, e lo stadio di probabilità d'incontro
/// (Bassa/Media/Alta, con colore) — niente barra di caricamento, dato che
/// sono solo tre stadi discreti, non un valore continuo.
/// `isLocked` (paywall, `features/paywall/`) sfoca solo la foto — distanza
/// e probabilità restano visibili anche bloccata, è proprio quel poco di
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _meetingChanceLabel(l10n, person.meetingChance),
                    style: TextStyle(
                      color: _meetingChanceColor(person.meetingChance),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.nearbyDistanceLabel(person.distanceMeters.round()),
                  ),
                ],
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
        return l10n.nearbyMeetingChanceLow;
      case MeetingChance.medium:
        return l10n.nearbyMeetingChanceMedium;
      case MeetingChance.high:
        return l10n.nearbyMeetingChanceHigh;
    }
  }

  Color _meetingChanceColor(MeetingChance chance) {
    switch (chance) {
      case MeetingChance.low:
        return Colors.redAccent;
      case MeetingChance.medium:
        return Colors.orangeAccent;
      case MeetingChance.high:
        return Colors.green;
    }
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

    return Stack(
      alignment: Alignment.center,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: image,
        ),
        Icon(
          Icons.lock,
          color: Colors.white,
          size: 28,
          shadows: [Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 6)],
        ),
      ],
    );
  }
}
