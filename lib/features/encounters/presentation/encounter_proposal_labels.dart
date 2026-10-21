import '/l10n/generated/app_localizations.dart';
import '../domain/entities/encounter_proposal.dart';

/// Testi ed emoji di ogni `EncounterProposal`, in un solo posto: tendina
/// della richiesta, richieste in entrata/uscita, intestazione del match. Non
/// è un widget: solo la traduzione da valore di dominio a testo.
///
/// Niente cuore né rosso (riservati al match), e l'emoji non porta mai da
/// sola il significato: chi la mostra la esclude dallo screen reader, il
/// testo accanto dice già tutto.
class EncounterProposalLabels {
  const EncounterProposalLabels._();

  /// 🥤 e non un bicchiere da vino o un boccale: "bere qualcosa", mai per
  /// forza alcolici. ☕/🤝/🙂 sono le stesse dei corrispondenti `MeetIntent`.
  static String emoji(EncounterProposal proposal) => switch (proposal) {
    EncounterProposal.sayHi => '👋',
    EncounterProposal.chat => '☕',
    EncounterProposal.friendship => '🤝',
    EncounterProposal.getToKnow => '🙂',
    EncounterProposal.drink => '🥤',
  };

  /// Come la sceglie chi chiede ("Bere qualcosa"), e come la rivede sulla
  /// propria richiesta in uscita.
  static String label(AppLocalizations l10n, EncounterProposal proposal) =>
      switch (proposal) {
        EncounterProposal.sayHi => l10n.proposal_label_say_hi,
        EncounterProposal.chat => l10n.proposal_label_chat,
        EncounterProposal.friendship => l10n.proposal_label_friendship,
        EncounterProposal.getToKnow => l10n.proposal_label_get_to_know,
        EncounterProposal.drink => l10n.proposal_label_drink,
      };

  /// Come la legge chi la riceve ("Vuole bere qualcosa insieme a te"),
  /// neutra rispetto al genere di chi chiede.
  static String received(AppLocalizations l10n, EncounterProposal proposal) =>
      switch (proposal) {
        EncounterProposal.sayHi => l10n.proposal_received_say_hi,
        EncounterProposal.chat => l10n.proposal_received_chat,
        EncounterProposal.friendship => l10n.proposal_received_friendship,
        EncounterProposal.getToKnow => l10n.proposal_received_get_to_know,
        EncounterProposal.drink => l10n.proposal_received_drink,
      };

  /// Il sottotitolo dell'intestazione "È un incontro!" ("Bere qualcosa
  /// insieme"), uguale per i due lati.
  static String matchSubtitle(
    AppLocalizations l10n,
    EncounterProposal proposal,
  ) => switch (proposal) {
    EncounterProposal.sayHi => l10n.match_proposal_say_hi,
    EncounterProposal.chat => l10n.match_proposal_chat,
    EncounterProposal.friendship => l10n.match_proposal_friendship,
    EncounterProposal.getToKnow => l10n.match_proposal_get_to_know,
    EncounterProposal.drink => l10n.match_proposal_drink,
  };

  /// Il suggerimento per il primo messaggio, adatto alla proposta.
  static String icebreaker(AppLocalizations l10n, EncounterProposal proposal) =>
      switch (proposal) {
        EncounterProposal.sayHi => l10n.match_icebreaker_say_hi,
        EncounterProposal.chat => l10n.match_icebreaker_chat,
        EncounterProposal.friendship => l10n.match_icebreaker_friendship,
        EncounterProposal.getToKnow => l10n.match_icebreaker_get_to_know,
        EncounterProposal.drink => l10n.match_icebreaker_drink,
      };
}
