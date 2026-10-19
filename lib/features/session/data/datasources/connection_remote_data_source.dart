import '/features/session/domain/entities/connection_status.dart';
import '/features/session/domain/entities/server_handshake.dart';

/// Contratto per osservare la connessione in tempo reale condivisa
/// (`RealtimeConnection`, in `core/network/`). Nessun model/JSON: legge e
/// scrive direttamente le entity, come `SessionLocalDataSource`.
abstract class ConnectionRemoteDataSource {
  /// Lo stato attuale subito, poi ogni cambiamento.
  Stream<ConnectionStatus> watchStatus();

  /// Ogni `welcome` del server, con il suo `resumed` e se è il primo
  /// della sessione.
  Stream<ServerHandshake> watchHandshakes();

  /// Controlla che il socket sia davvero vivo (ping, risposta attesa per
  /// pochi secondi) e, se non lo è, riconnette subito. Senza sessione non
  /// fa nulla.
  void checkAlive();
}
