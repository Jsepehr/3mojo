import 'package:flutter/material.dart';

import '/core/utils/photo_data_uri.dart';
import '/core/widgets/cmp_photo.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/l10n/generated/app_localizations.dart';

/// Riga della lista "Vicinanze": nessun nome (l'app non lo chiede), solo
/// una foto grande, la distanza, e lo stadio di probabilità d'incontro
/// (Bassa/Media/Alta, con colore) — niente barra di caricamento, dato che
/// sono solo tre stadi discreti, non un valore continuo.
class CmpNearbyPersonTile extends StatelessWidget {
  const CmpNearbyPersonTile({super.key, required this.person});

  final NearbyPerson person;

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
            CmpPhoto(image: photo, size: 96),
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
