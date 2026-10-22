import 'package:flutter/material.dart';

import '/core/theme/raen_colors.dart';
import '/core/utils/photo_data_uri.dart';
import '/core/widgets/cmp_photo.dart';
import '/core/widgets/cmp_status_chip.dart';
import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/encounter_request.dart';
import '../encounter_proposal_labels.dart';

/// Riga di una richiesta mandata da te: cosa hai proposto (emoji +
/// etichetta breve, "🥤 Bere qualcosa") e il suo stato come chip: in
/// attesa (orologio, neutro), accettata (cuore pieno, rosso-cuore: la buona
/// notizia), "non questa volta"/annullata/finita (croce, solo bordo — uno
/// stato chiuso che non deve attirare l'occhio). [trailing] (facoltativo)
/// è il menu "⋯" con Segnala e Blocca, composto da `UiEncounters`.
class CmpOutgoingRequestTile extends StatelessWidget {
  const CmpOutgoingRequestTile({
    super.key,
    required this.request,
    this.trailing,
  });

  final EncounterRequest request;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final photo = imageProviderForPhoto(request.otherSelfieBytes);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CmpPhoto(image: photo, size: 56),
      trailing: trailing,
      title: Row(
        children: [
          ExcludeSemantics(
            child: Text(EncounterProposalLabels.emoji(request.proposal)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              EncounterProposalLabels.label(l10n, request.proposal),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: _statusChip(context, l10n, request.status),
        ),
      ),
    );
  }

  Widget _statusChip(
    BuildContext context,
    AppLocalizations l10n,
    EncounterRequestStatus status,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final raen = RaenColors.of(context);

    CmpStatusChip closed(String label) => CmpStatusChip(
      label: label,
      icon: Icons.close,
      foreground: colorScheme.onSurfaceVariant,
      outlined: true,
    );

    switch (status) {
      case EncounterRequestStatus.pending:
        return CmpStatusChip(
          label: l10n.waiting_for_a_reply,
          icon: Icons.schedule,
          background: colorScheme.secondaryContainer,
          foreground: colorScheme.onSecondaryContainer,
        );
      case EncounterRequestStatus.accepted:
        return CmpStatusChip(
          label: l10n.accepted,
          icon: Icons.favorite,
          iconColor: raen.heart,
          background: raen.heartContainer,
          foreground: raen.onHeartContainer,
        );
      case EncounterRequestStatus.declined:
        return closed(l10n.declined);
      case EncounterRequestStatus.cancelled:
        return closed(l10n.cancelled_you_have_another_match);
      case EncounterRequestStatus.ended:
        return closed(l10n.ended);
    }
  }
}
