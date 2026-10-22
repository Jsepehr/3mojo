import '../../domain/entities/report_reason.dart';
import '../models/safety_rejection_model.dart';

/// Contratto verso il backend `server/` per bloccare e segnalare, sulla
/// connessione persistente condivisa (`RealtimeConnection`). Le azioni
/// partono subito o falliscono subito (`ServerException` se la connessione
/// non è pronta: "non inviato"); il server non conferma, l'effetto si vede
/// dagli snapshot di "Vicinanze" e delle richieste. Solo i rifiuti tornano
/// indietro ([watchRejections]).
abstract class SafetyRemoteDataSource {
  /// Lancia `ServerException` se non è partito.
  void block(String personId);

  /// Solo il codice del motivo, mai testo. Lancia `ServerException` se non
  /// è partita.
  void report({required String personId, required ReportReason reason});

  Stream<SafetyRejectionModel> watchRejections(String sessionId);

  /// Dimentica lo stato della sessione appena finita (il finto, che lo
  /// tiene in memoria).
  Future<void> reset();
}
