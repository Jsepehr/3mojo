import '/features/profile/domain/entities/profile.dart';
import '../entities/encounter_proposal.dart';
import 'proposal_for_intent_usecase.dart';

/// Regola: quale proposta trovi già scelta (in cima) aprendo la tendina
/// della richiesta. Prima l'**ultima che hai scelto in questa sessione**
/// ([lastChosen], tenuta solo in memoria e dimenticata a End); se non ce
/// n'è, quella abbinata al tuo intento di sessione
/// (`ProposalForIntentUseCase`): ☕ → due chiacchiere, 🤝 → amicizia, 🙂/✨
/// o nessun intento → "conoscerti".
class PreselectEncounterProposalUseCase {
  const PreselectEncounterProposalUseCase({
    ProposalForIntentUseCase proposalForIntentUseCase =
        const ProposalForIntentUseCase(),
  }) : _proposalForIntentUseCase = proposalForIntentUseCase;

  final ProposalForIntentUseCase _proposalForIntentUseCase;

  EncounterProposal call({
    EncounterProposal? lastChosen,
    MeetIntent? ownIntent,
  }) => lastChosen ?? _proposalForIntentUseCase(ownIntent);
}
