import '../entities/connection_status.dart';
import '../entities/server_handshake.dart';

/// Contratto per osservare il canale in tempo reale condiviso da `nearby`,
/// `encounters` e `chat` (una sola connessione per sessione). Non manda
/// nulla delle feature: serve solo a sapere come sta il collegamento (e a
/// verificarlo, [checkConnection]).
abstract class ConnectionRepository {
  /// Lo stato attuale subito, poi ogni cambiamento.
  Stream<ConnectionStatus> watchStatus();

  /// Ogni benvenuto del server (primo collegamento e riconnessioni).
  Stream<ServerHandshake> watchHandshakes();

  /// Verifica che il collegamento sia davvero vivo e, se non lo è (o se si
  /// stava aspettando il prossimo tentativo), riconnette subito. Non
  /// fallisce: l'esito si vede da [watchStatus].
  void checkConnection();
}
