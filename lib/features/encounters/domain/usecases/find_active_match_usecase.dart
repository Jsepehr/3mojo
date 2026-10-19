import '../entities/encounter_request.dart';

/// Azione (pura, senza I/O): qual è il match attivo tra queste richieste?
/// La richiesta accettata (al più una: "un solo incontro alla volta" lo
/// garantisce il server), escluse quelle che hai appena chiuso tu
/// ([locallyEndedIds]: uno snapshot ancora in volo che le mostra accettate
/// non deve riaprire la pagina del match).
///
/// La usano `ProEncounters.activeMatch` e `DetectEndedMatchUseCase`, così
/// la regola è scritta una volta sola.
class FindActiveMatchUseCase {
  const FindActiveMatchUseCase();

  EncounterRequest? call(
    Iterable<EncounterRequest> requests, {
    Set<String> locallyEndedIds = const {},
  }) {
    for (final request in requests) {
      if (request.status == EncounterRequestStatus.accepted &&
          !locallyEndedIds.contains(request.id)) {
        return request;
      }
    }
    return null;
  }
}
