/// Cosa propone chi manda una richiesta d'incontro: la frase che l'altra
/// persona legge ("vuole salutarti", "vuole bere qualcosa insieme a te"…).
///
/// **Lista chiusa** apposta, come `MeetIntent`: niente testo libero (da
/// moderare, e che collegherebbe le sessioni tra loro), niente opzioni
/// romantiche. Sul filo viaggia solo il nome del valore (`sayHi`, `chat`,
/// `friendship`, `getToKnow`, `drink`): sono codici **stabili**, gli stessi
/// di `EncounterProposal` nel server (`server/lib/src/encounter_proposal.dart`)
/// — non rinominarli senza cambiare anche l'altro lato. La frase la traduce
/// il telefono di chi la riceve, nella sua lingua.
///
/// Non è `MeetIntent` (cosa si cerca stasera, mostrato a tutti in
/// "Vicinanze"): questa è la proposta fatta a **una** persona, con una
/// richiesta. I due si parlano solo tramite `ProposalForIntentUseCase`.
enum EncounterProposal {
  sayHi,
  chat,
  friendship,
  getToKnow,
  drink;

  /// La proposta di ripiego: quella neutra di sempre ("vuole conoscerti"),
  /// per un codice mancante o sconosciuto e quando non c'è altro da cui
  /// partire.
  static const fallback = EncounterProposal.getToKnow;
}
