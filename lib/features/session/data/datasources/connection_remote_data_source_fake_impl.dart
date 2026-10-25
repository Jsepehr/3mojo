import '/features/session/domain/entities/connection_status.dart';
import '/features/session/domain/entities/server_handshake.dart';
import 'connection_remote_data_source.dart';

/// Implementazione **finta** del collegamento, per la demo dichiarata
/// (`DemoScope`): non c'è nessun `RealtimeConnection` dietro — la demo non
/// apre mai un WebSocket. Sempre "collegati" (nessun indicatore di
/// riconnessione), nessun benvenuto del server, nessuna chiusura da parte
/// sua; [checkAlive] non fa nulla.
class ConnectionRemoteDataSourceFakeImpl implements ConnectionRemoteDataSource {
  @override
  Stream<ConnectionStatus> watchStatus() =>
      Stream.value(ConnectionStatus.online);

  @override
  Stream<ServerHandshake> watchHandshakes() => const Stream.empty();

  @override
  Stream<void> watchSessionClosures() => const Stream.empty();

  @override
  void checkAlive() {}
}
