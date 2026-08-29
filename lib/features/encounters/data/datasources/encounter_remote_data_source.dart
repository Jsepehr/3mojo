import '../models/encounter_request_model.dart';

/// Contratto verso il backend `server/`: le richieste in entrata/uscita
/// arrivano spinte dal server sulla connessione persistente condivisa con
/// `nearby` (vedi `RealtimeConnection`), non richieste una alla volta —
/// mandare/rispondere sono azioni fire-and-forget: l'esito (compresa la
/// regola "un solo incontro alla volta", applicata dal server) arriva col
/// prossimo snapshot.
abstract class EncounterRemoteDataSource {
  /// Stream degli snapshot `{incoming, outgoing}` per `sessionId` — uno
  /// ogni volta che qualcosa cambia (nuova richiesta, risposta, match,
  /// fine). Apre la connessione condivisa se non già aperta.
  Stream<({List<EncounterRequestModel> incoming, List<EncounterRequestModel> outgoing})>
  watchRequests(String sessionId);

  void sendRequest({required String otherPersonId});

  void respondToRequest({required String requestId, required bool accepted});

  void endMatch(String requestId);
}
