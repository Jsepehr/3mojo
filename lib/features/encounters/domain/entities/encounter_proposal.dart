/// Cosa propone chi manda una richiesta d'incontro: la frase che l'altra
/// persona legge ("vuole fare due chiacchiere", "vuole bere qualcosa insieme a te"…).
///
/// **Lista chiusa** apposta, come `MeetPlace`: niente testo libero (da
/// moderare, e che collegherebbe le sessioni tra loro), niente opzioni
/// romantiche. Sul filo viaggia solo il nome del valore (`chat`,
/// `friendship`, `getToKnow`, `drink`, `dance`): sono codici **stabili**, gli stessi
/// di `EncounterProposal` nel server (`server/lib/src/encounter_proposal.dart`)
/// — non rinominarli senza cambiare anche l'altro lato. La frase la traduce
/// il telefono di chi la riceve, nella sua lingua.
///
/// Non è `MeetPlace` (dove ci si trova, mostrato a tutti in "Vicinanze"):
/// questa è la proposta fatta a **una** persona, con una richiesta. Quali se
/// ne offrono dipende dal luogo di chi chiede (`ProposalsForPlaceUseCase`).
///
/// 💃 `dance` è arrivata dopo le altre: un server più vecchio non la
/// conosce e la legge come [fallback] (compatibile, nessun errore).
enum EncounterProposal {
  chat,
  friendship,
  getToKnow,
  drink,
  dance;

  /// La proposta di ripiego: quella neutra di sempre ("vuole conoscerti"),
  /// per un codice mancante o sconosciuto e quando non c'è altro da cui
  /// partire.
  static const fallback = EncounterProposal.getToKnow;
}
