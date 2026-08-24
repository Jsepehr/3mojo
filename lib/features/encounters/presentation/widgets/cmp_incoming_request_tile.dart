import 'package:flutter/material.dart';

import '/core/utils/photo_data_uri.dart';
import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/encounter_request.dart';

/// Scheda "qualcuno vuole conoscerti": foto + bottoni sì/no.
class CmpIncomingRequestTile extends StatelessWidget {
  const CmpIncomingRequestTile({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  final EncounterRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final photo = imageProviderForPhoto(request.otherSelfiePath);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundImage: photo,
              child: photo == null ? const Icon(Icons.person, size: 32) : null,
            ),
            const SizedBox(height: 12),
            Text(l10n.encountersWantsToMeetYou, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: onDecline,
                  child: Text(l10n.encountersDeclineButton),
                ),
                FilledButton(
                  onPressed: onAccept,
                  child: Text(l10n.encountersAcceptButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
