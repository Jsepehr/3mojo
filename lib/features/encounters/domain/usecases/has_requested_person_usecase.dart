import '../entities/encounter_request.dart';

/// Azione (pura, senza I/O): con questa persona c'è già una richiesta in
/// questa sessione? È la regola "una sola richiesta a testa": vale per
/// qualsiasi richiesta tra i due, mandata **o** ricevuta, in qualsiasi
/// stato (anche rifiutata: niente rimandare) — la stessa che applica il
/// server (`alreadyRequested`), che resta l'autorità. La fonte sono le
/// richieste dello snapshot del server ([requests]), più quelle appena
/// partite che lo snapshot non mostra ancora ([awaitingPersonIds]).
///
/// La usano sia `SendEncounterRequestUseCase` (per non mandarla) sia la UI
/// (per mostrare la persona come già richiesta), così la regola è scritta
/// una volta sola.
class HasRequestedPersonUseCase {
  const HasRequestedPersonUseCase();

  bool call(
    String otherPersonId, {
    required Iterable<EncounterRequest> requests,
    Set<String> awaitingPersonIds = const {},
  }) =>
      awaitingPersonIds.contains(otherPersonId) ||
      requests.any((request) => request.otherPersonId == otherPersonId);
}
