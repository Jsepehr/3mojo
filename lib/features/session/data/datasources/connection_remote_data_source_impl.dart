import 'dart:async';

import '/core/network/realtime_connection.dart';
import '/features/session/domain/entities/connection_status.dart';
import '/features/session/domain/entities/server_handshake.dart';
import 'connection_remote_data_source.dart';

/// Implementazione **reale** sopra `RealtimeConnection`. Conta i `welcome`
/// di ogni sessione (il conteggio riparte quando una sessione nuova inizia
/// a collegarsi, `connecting`, o finisce, `offline`), così ogni benvenuto
/// esce già marcato come primo o no — indipendentemente da quando qualcuno
/// si mette in ascolto. Va creato all'avvio dell'app (in `app.dart` il suo
/// provider non è pigro), prima del primo collegamento.
///
/// In modalità finta nessuno usa `RealtimeConnection`: lo stato resta
/// `offline` e non arriva nessun benvenuto — nessun indicatore a schermo.
class ConnectionRemoteDataSourceImpl implements ConnectionRemoteDataSource {
  ConnectionRemoteDataSourceImpl({RealtimeConnection? connection})
    : _connection = connection ?? RealtimeConnection.instance {
    _connection.statusChanges.listen((status) {
      if (status == RealtimeStatus.connecting ||
          status == RealtimeStatus.offline) {
        _handshakesThisSession = 0;
      }
    });
    _connection.onReady.listen((resumed) {
      _handshakesThisSession++;
      _handshakes.add(
        ServerHandshake(
          resumed: resumed,
          isFirstOfSession: _handshakesThisSession == 1,
        ),
      );
    });
  }

  final RealtimeConnection _connection;
  final StreamController<ServerHandshake> _handshakes =
      StreamController.broadcast();
  int _handshakesThisSession = 0;

  @override
  Stream<ConnectionStatus> watchStatus() => Stream.multi((controller) {
    controller.add(_toStatus(_connection.status));
    final subscription = _connection.statusChanges.listen(
      (status) => controller.add(_toStatus(status)),
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  });

  @override
  Stream<ServerHandshake> watchHandshakes() => _handshakes.stream;

  @override
  void checkAlive() => _connection.checkAlive();

  static ConnectionStatus _toStatus(RealtimeStatus status) => switch (status) {
    RealtimeStatus.offline => ConnectionStatus.offline,
    RealtimeStatus.connecting => ConnectionStatus.connecting,
    RealtimeStatus.online => ConnectionStatus.online,
    RealtimeStatus.reconnecting => ConnectionStatus.reconnecting,
  };
}
