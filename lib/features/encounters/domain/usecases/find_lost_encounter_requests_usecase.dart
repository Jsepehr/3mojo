/// Azione (pura, senza I/O): quali richieste d'incontro, partite verso il
/// server ma non ancora confermate (nessuno snapshot le mostra) né
/// rifiutate, vanno considerate **perse**?
///
/// Regola: una richiesta non confermata entro [confirmationTimeout] dalla
/// partenza è persa. Il server conferma con lo snapshot in pochi
/// millisecondi; se non arriva nulla, il frame si è perso con un socket
/// morto (partito "con successo" verso un canale che non portava più
/// nulla). Senza questa regola la persona resterebbe "richiesta" per tutta
/// la sessione, senza che la richiesta esista sul server — e senza poterla
/// rimandare. Se invece era arrivata, rimandarla dà `alreadyRequested` e lo
/// snapshot successivo la mostra comunque: nessun danno.
class FindLostEncounterRequestsUseCase {
  const FindLostEncounterRequestsUseCase();

  static const confirmationTimeout = Duration(seconds: 10);

  /// [sentAtByPersonId]: per ogni persona, quando è partita la richiesta.
  /// Ritorna le persone la cui richiesta è da considerare persa a [now].
  Set<String> call(
    Map<String, DateTime> sentAtByPersonId, {
    required DateTime now,
  }) => {
    for (final entry in sentAtByPersonId.entries)
      if (now.difference(entry.value) >= confirmationTimeout) entry.key,
  };
}
