import '/features/profile/domain/entities/profile.dart';
import '../entities/encounter_proposal.dart';

/// Regola: quale proposta "va d'accordo" con un intento di sessione
/// (`MeetIntent`). ☕ due chiacchiere → [EncounterProposal.chat], 🤝
/// amicizia → [EncounterProposal.friendship]; 🙂 conoscere gente, ✨ aperto
/// a tutto e nessun intento → [EncounterProposal.getToKnow] (la frase
/// neutra).
///
/// Serve due volte, sempre con un intento **pubblico**: il proprio, per
/// preselezionare la proposta (`PreselectEncounterProposalUseCase`), e
/// quello che l'altra persona mostra in "Vicinanze", per segnare la
/// proposta "in linea con ciò che cerca" — mai con dati privati (chi cerca,
/// genere).
class ProposalForIntentUseCase {
  const ProposalForIntentUseCase();

  EncounterProposal call(MeetIntent? intent) => switch (intent) {
    MeetIntent.chat => EncounterProposal.chat,
    MeetIntent.friendship => EncounterProposal.friendship,
    MeetIntent.meetPeople ||
    MeetIntent.openToAnything ||
    null => EncounterProposal.fallback,
  };
}
