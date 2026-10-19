import '/features/session/data/datasources/connection_remote_data_source.dart';
import '/features/session/domain/entities/connection_status.dart';
import '/features/session/domain/entities/server_handshake.dart';
import '/features/session/domain/repositories/connection_repository.dart';

/// Passacarte verso il datasource: osservare (o controllare) la
/// connessione non può fallire (nessuna eccezione da tradurre).
class ConnectionRepositoryImpl implements ConnectionRepository {
  const ConnectionRepositoryImpl(this._remoteDataSource);

  final ConnectionRemoteDataSource _remoteDataSource;

  @override
  Stream<ConnectionStatus> watchStatus() => _remoteDataSource.watchStatus();

  @override
  Stream<ServerHandshake> watchHandshakes() =>
      _remoteDataSource.watchHandshakes();

  @override
  void checkConnection() => _remoteDataSource.checkAlive();
}
