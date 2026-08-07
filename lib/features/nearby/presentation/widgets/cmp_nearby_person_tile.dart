import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/nearby_person.dart';

class CmpNearbyPersonTile extends StatelessWidget {
  const CmpNearbyPersonTile({super.key, required this.person});

  final NearbyPerson person;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final percent = person.meetingChancePercent;

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: person.photoUrl.isEmpty
            ? null
            : NetworkImage(person.photoUrl),
        child: person.photoUrl.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(person.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _meetingChanceLabel(l10n, percent),
            style: TextStyle(color: _meetingChanceColor(percent)),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 4,
              color: _meetingChanceColor(percent),
            ),
          ),
        ],
      ),
      trailing: Text(l10n.nearbyDistanceLabel(person.distanceMeters.round())),
    );
  }

  String _meetingChanceLabel(AppLocalizations l10n, int percent) {
    if (percent < 34) return l10n.nearbyMeetingChanceLow;
    if (percent < 67) return l10n.nearbyMeetingChanceMedium;
    return l10n.nearbyMeetingChanceHigh;
  }

  Color _meetingChanceColor(int percent) {
    if (percent < 34) return Colors.redAccent;
    if (percent < 67) return Colors.orangeAccent;
    return Colors.green;
  }
}
