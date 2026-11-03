import '/features/session/domain/entities/meet_place.dart';
import '../entities/encounter_proposal.dart';
import 'proposals_for_place_usecase.dart';

/// Regola: quale proposta trovi già scelta (in cima) aprendo la tendina
/// della richiesta. Prima l'**ultima che hai scelto in questa sessione**
/// ([lastChosen], tenuta solo in memoria e dimenticata a End) **se è ancora
/// tra quelle previste per il tuo luogo** (`ProposalsForPlaceUseCase`);
/// altrimenti la prima di quelle del luogo. Con [otherPlace] diverso dal tuo
/// restano solo le neutre (vedi `ProposalsForPlaceUseCase`).
class PreselectEncounterProposalUseCase {
  const PreselectEncounterProposalUseCase({
    ProposalsForPlaceUseCase proposalsForPlaceUseCase =
        const ProposalsForPlaceUseCase(),
  }) : _proposalsForPlaceUseCase = proposalsForPlaceUseCase;

  final ProposalsForPlaceUseCase _proposalsForPlaceUseCase;

  EncounterProposal call({
    EncounterProposal? lastChosen,
    MeetPlace ownPlace = MeetPlace.fallback,
    MeetPlace otherPlace = MeetPlace.fallback,
  }) {
    final available = _proposalsForPlaceUseCase(
      ownPlace,
      otherPlace: otherPlace,
    );
    return lastChosen != null && available.contains(lastChosen)
        ? lastChosen
        : available.first;
  }
}
