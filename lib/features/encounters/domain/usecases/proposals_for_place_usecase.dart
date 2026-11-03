import '/features/session/domain/entities/meet_place.dart';
import '../entities/encounter_proposal.dart';

/// Regola: quali proposte si offrono a chi manda una richiesta dal luogo
/// [MeetPlace] in cui si trova (il **proprio**, scelto allo Start), nell'ordine
/// in cui compaiono — la prima è quella preselezionata di partenza.
///
/// Sono sempre due, tranne per [MeetPlace.other] (quattro, come prima che
/// esistessero i luoghi: chi non dichiara nulla non ha restrizioni). Mai
/// opzioni romantiche. Il server accetta comunque ogni codice della lista
/// chiusa: questa è una guida per chi chiede, non un controllo di sicurezza.
class ProposalsForPlaceUseCase {
  const ProposalsForPlaceUseCase();

  List<EncounterProposal> call(MeetPlace place) => switch (place) {
    MeetPlace.bar => const [EncounterProposal.drink, EncounterProposal.chat],
    MeetPlace.cafe => const [
      EncounterProposal.chat,
      EncounterProposal.getToKnow,
    ],
    MeetPlace.discoPub ||
    MeetPlace.club => const [EncounterProposal.dance, EncounterProposal.drink],
    MeetPlace.event => const [
      EncounterProposal.dance,
      EncounterProposal.friendship,
    ],
    MeetPlace.outdoors => const [
      EncounterProposal.chat,
      EncounterProposal.friendship,
    ],
    MeetPlace.other => const [
      EncounterProposal.chat,
      EncounterProposal.friendship,
      EncounterProposal.getToKnow,
      EncounterProposal.drink,
    ],
  };
}
