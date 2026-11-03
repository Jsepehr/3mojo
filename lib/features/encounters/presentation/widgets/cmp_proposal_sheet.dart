import 'dart:typed_data';

import 'package:flutter/material.dart';

import '/core/utils/photo_data_uri.dart';
import '/core/widgets/cmp_photo.dart';
import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/encounter_proposal.dart';
import '../encounter_proposal_labels.dart';

/// Apre la tendina "Cosa vuoi proporre?" per la persona con foto
/// [photoBytes] e ritorna la proposta toccata (la richiesta la manda chi
/// chiama), o `null` se la si chiude senza scegliere. Con le animazioni di
/// sistema ridotte (`MediaQuery.disableAnimations`) compare e sparisce
/// senza scorrere.
Future<EncounterProposal?> showProposalSheet(
  BuildContext context, {
  required Uint8List? photoBytes,
  required EncounterProposal preselected,
  required List<EncounterProposal> proposals,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<EncounterProposal>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: reduceMotion ? AnimationStyle.noAnimation : null,
    builder: (sheetContext) => CmpProposalSheet(
      photoBytes: photoBytes,
      preselected: preselected,
      proposals: proposals,
      onChoose: (proposal) => Navigator.of(sheetContext).pop(proposal),
    ),
  );
}

/// Contenuto della tendina della richiesta d'incontro: in alto la foto
/// piccola della persona, poi le proposte previste per il **tuo** luogo (`ProposalsForPlaceUseCase`) come righe
/// grandi da toccare — la [preselected] in cima ed evidenziata — e in fondo
/// cosa vedrà l'altra persona. Toccare una riga **è** l'invio (2 tap in
/// tutto, dalla lista "Vicinanze"): [onChoose].
///
class CmpProposalSheet extends StatelessWidget {
  const CmpProposalSheet({
    super.key,
    required this.photoBytes,
    required this.preselected,
    required this.onChoose,
    required this.proposals,
  });

  final Uint8List? photoBytes;
  final EncounterProposal preselected;
  final List<EncounterProposal> proposals;
  final ValueChanged<EncounterProposal> onChoose;

  /// La preselezionata in cima, le altre nell'ordine di [proposals].
  List<EncounterProposal> get orderedProposals => [
    preselected,
    for (final proposal in proposals)
      if (proposal != preselected) proposal,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Decorativa qui: chi usa lo screen reader ha appena toccato
              // questa persona nella lista.
              ExcludeSemantics(
                child: CmpPhoto(
                  image: imageProviderForPhoto(photoBytes),
                  size: 56,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.proposal_sheet_title,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final proposal in orderedProposals) ...[
            _ProposalRow(
              key: ValueKey('proposal-${proposal.name}'),
              proposal: proposal,
              isPreselected: proposal == preselected,
              onTap: () => onChoose(proposal),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 16, color: mutedColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.proposal_sheet_footer,
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Una proposta: emoji (esclusa dallo screen reader) + etichetta, alta
/// almeno 56 dp. La preselezionata ha il fondo `primaryContainer`.
class _ProposalRow extends StatelessWidget {
  const _ProposalRow({
    super.key,
    required this.proposal,
    required this.isPreselected,
    required this.onTap,
  });

  final EncounterProposal proposal;
  final bool isPreselected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final background = isPreselected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHigh;
    final foreground = isPreselected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final muted = isPreselected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: isPreselected,
      onTapHint: l10n.proposal_send_hint,
      child: Material(
        color: background,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Text(
                      EncounterProposalLabels.emoji(proposal),
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          EncounterProposalLabels.label(l10n, proposal),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ExcludeSemantics(
                    child: Icon(Icons.send_rounded, size: 20, color: muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
