import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/core/utils/photo_data_uri.dart';
import '/core/widgets/cmp_photo.dart';
import '/features/profile/presentation/profile_labels.dart';
import '/features/profile/presentation/widgets/cmp_profile_details.dart';
import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/encounter_request.dart';
import '../encounter_proposal_labels.dart';

/// Scheda di una richiesta in arrivo: la foto, poi cosa ti propone
/// ("🥤 Vuole bere qualcosa insieme a te") come riga principale, poi ciò che
/// mostra dal profilo, e i bottoni "No, grazie"/"Sì" (con un tic di
/// vibrazione a ogni risposta).
///
/// Il "Sì" ha una spunta neutra, non il cuore: si accetta una proposta
/// (due chiacchiere, bere qualcosa…), non per forza un appuntamento.
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
    final theme = Theme.of(context);
    final photo = imageProviderForPhoto(request.otherSelfieBytes);
    final proposal = request.proposal;
    // Se l'intento che mostra ha la stessa emoji della proposta (☕, 🤝, 🙂)
    // direbbe due volte la stessa cosa: resta solo la proposta.
    final intent = request.otherIntent;
    final shownIntent =
        intent != null &&
            ProfileLabels.intentEmoji(intent) ==
                EncounterProposalLabels.emoji(proposal)
        ? null
        : intent;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CmpPhoto(image: photo, size: 96),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Text(
                    EncounterProposalLabels.emoji(proposal),
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    EncounterProposalLabels.received(l10n, proposal),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            // Ciò che la persona mostra dal proprio profilo, per decidere
            // sapendo cosa cerca — mai chi cerca.
            if (CmpProfileDetails.hasAny(
              intent: shownIntent,
              languages: request.otherLanguages,
              visibleGender: request.otherVisibleGender,
            )) ...[
              const SizedBox(height: 8),
              CmpProfileDetails(
                intent: shownIntent,
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
                  child: Text(l10n.no_thanks),
                ),
                FilledButton.icon(
                  onPressed: () => _answer(onAccept),
                  icon: const Icon(Icons.check),
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
