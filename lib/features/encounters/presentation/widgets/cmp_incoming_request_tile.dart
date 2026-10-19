import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/core/theme/raen_colors.dart';
import '/core/utils/photo_data_uri.dart';
import '/core/widgets/cmp_photo.dart';
import '/features/profile/presentation/widgets/cmp_profile_details.dart';
import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/encounter_request.dart';

/// Scheda "qualcuno vuole conoscerti": foto + bottoni sì/no (con un tic
/// di vibrazione a ogni risposta).
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

  void _answer(VoidCallback answer) {
    HapticFeedback.selectionClick();
    answer();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final raen = RaenColors.of(context);
    final photo = imageProviderForPhoto(request.otherSelfieBytes);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CmpPhoto(image: photo, size: 96),
            const SizedBox(height: 12),
            Text(
              l10n.this_person_wants_to_meet_you,
              textAlign: TextAlign.center,
            ),
            // Ciò che la persona mostra dal proprio profilo, per decidere
            // sapendo cosa cerca — mai chi cerca.
            if (CmpProfileDetails.hasAny(
              intent: request.otherIntent,
              languages: request.otherLanguages,
              visibleGender: request.otherVisibleGender,
            )) ...[
              const SizedBox(height: 8),
              CmpProfileDetails(
                intent: request.otherIntent,
                languages: request.otherLanguages,
                visibleGender: request.otherVisibleGender,
                alignment: WrapAlignment.center,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: () => _answer(onDecline),
                  child: Text(l10n.no),
                ),
                // "Sì" è la CTA del cuore: rosso-cuore col glifo ♥, mai
                // confondibile col rosso di End/errori.
                FilledButton.icon(
                  onPressed: () => _answer(onAccept),
                  style: FilledButton.styleFrom(
                    backgroundColor: raen.heart,
                    foregroundColor: raen.onHeart,
                  ),
                  icon: const Icon(Icons.favorite),
                  label: Text(l10n.yes),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
