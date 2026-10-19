import '../models/encounter_rejection_model.dart';
import '../models/encounter_request_model.dart';

/// Uno snapshot completo delle richieste della sessione.
typedef EncounterSnapshotModel = ({
  List<EncounterRequestModel> incoming,
  List<EncounterRequestModel> outgoing,
});

/// Contratto verso il backend `server/`: le richieste in entrata/uscita
/// arrivano spinte dal server sulla connessione persistente condivisa con
/// `nearby` (vedi `RealtimeConnection`), non richieste una alla volta.
/// Mandare/rispondere/chiudere un match partono subito o falliscono subito
/// (`ServerException` se la connessione non è pronta: "non inviato"); l'esito
/// vero (compresa la regola "un solo incontro alla volta", applicata dal
/// server) arriva col prossimo snapshot.
abstract class EncounterRemoteDataSource {
  /// Stream degli snapshot `{incoming, outgoing}` per `sessionId` — uno
  /// ogni volta che qualcosa cambia (nuova richiesta, risposta, match,
  /// fine). Apre la connessione condivisa se non già aperta. Se la
  /// connessione cade emette un errore ma non si chiude (riconnessione
  /// automatica); finisce quando finisce la sessione.
  Stream<EncounterSnapshotModel> watchRequests(String sessionId);

  /// Le azioni (mandare, rispondere) che il server ha ricevuto ma
  /// rifiutato, col motivo. Gli errori di connessione non passano di qui
  /// (li racconta già [watchRequests]).
  Stream<EncounterRejectionModel> watchRejections(String sessionId);

  /// Lancia `ServerException` se non è partita.
  void sendRequest({required String otherPersonId});

  /// Lancia `ServerException` se non è partita.
  void respondToRequest({required String requestId, required bool accepted});

  /// Lancia `ServerException` se non è partita.
  void endMatch(String requestId);

  /// Dimentica tutto lo stato della sessione appena finita (End). Per il
  /// datasource reale non c'è nulla da fare (lo stato vive sul server, e lo
  /// stream si chiude con la connessione); quello finto, che lo stato lo
  /// tiene in memoria, lo azzera e chiude il suo stream.
  Future<void> reset();
}
