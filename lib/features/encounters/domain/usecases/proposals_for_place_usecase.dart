import '/features/session/domain/entities/meet_place.dart';
import '../entities/encounter_proposal.dart';

/// Regola: quali proposte si offrono a chi manda una richiesta dal luogo
/// [MeetPlace] in cui si trova (il **proprio**, scelto allo Start), nell'ordine
/// in cui compaiono — la prima è quella preselezionata di partenza.
///
/// Le proposte tipiche del luogo vengono per prime e [EncounterProposal
/// .getToKnow] (la neutra, di ripiego) chiude sempre la lista: anche dove
/// si balla o si beve, chi non vuole né l'una né l'altra deve poter dire
/// solo "vuole conoscerti". [MeetPlace.other] ha tutte e quattro, come
/// prima che esistessero i luoghi: chi non dichiara nulla non ha
/// restrizioni. Mai opzioni romantiche. Il server accetta comunque ogni codice della lista
/// chiusa: questa è una guida per chi chiede, non un controllo di sicurezza.
///
/// Se la persona a cui scrivi ha dichiarato un luogo **diverso** dal tuo
/// ([otherPlace], e anche il tuo è dichiarato: sono nello stesso raggio ma in
/// locali diversi) le proposte legate al posto — [placeSpecific], ballare e
/// bere qualcosa — non hanno senso per lei: restano solo quelle neutre. Se
/// uno dei due non dichiara niente, o i luoghi coincidono, nessuna
/// restrizione.
class ProposalsForPlaceUseCase {
  const ProposalsForPlaceUseCase();

  /// Le proposte che hanno senso solo nel posto giusto.
  static const placeSpecific = {
    EncounterProposal.dance,
    EncounterProposal.drink,
  };

  List<EncounterProposal> call(
    MeetPlace place, {
    MeetPlace otherPlace = MeetPlace.fallback,
  }) {
    final proposals = _of(place);
    final differentPlaces =
        place.isDeclared && otherPlace.isDeclared && place != otherPlace;
    if (!differentPlaces) return proposals;
    return [
      for (final proposal in proposals)
        if (!placeSpecific.contains(proposal)) proposal,
    ];
  }

  static List<EncounterProposal> _of(MeetPlace place) => switch (place) {
    MeetPlace.bar => const [
      EncounterProposal.drink,
      EncounterProposal.chat,
      EncounterProposal.getToKnow,
    ],
    MeetPlace.cafe => const [
      EncounterProposal.chat,
      EncounterProposal.getToKnow,
    ],
    MeetPlace.discoPub || MeetPlace.club => const [
      EncounterProposal.dance,
      EncounterProposal.drink,
      EncounterProposal.getToKnow,
    ],
    MeetPlace.event => const [
      EncounterProposal.dance,
      EncounterProposal.friendship,
      EncounterProposal.getToKnow,
    ],
    MeetPlace.outdoors => const [
      EncounterProposal.chat,
      EncounterProposal.friendship,
      EncounterProposal.getToKnow,
    ],
    MeetPlace.other => const [
      EncounterProposal.chat,
      EncounterProposal.friendship,
      EncounterProposal.getToKnow,
      EncounterProposal.drink,
    ],
  };
}
