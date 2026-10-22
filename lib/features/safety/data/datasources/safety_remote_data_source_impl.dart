import '/core/errors/exceptions.dart';
import '/core/network/realtime_connection.dart';
import '../../domain/entities/report_reason.dart';
import '../models/safety_rejection_model.dart';
import 'safety_remote_data_source.dart';

/// Implementazione **reale**: `block`/`report` sulla connessione WebSocket
/// condivisa (vedi `server/routes/ws.dart`).
class SafetyRemoteDataSourceImpl implements SafetyRemoteDataSource {
  SafetyRemoteDataSourceImpl({RealtimeConnection? connection})
    : _connection = connection ?? RealtimeConnection.instance;

  final RealtimeConnection _connection;

  void _send(Map<String, dynamic> message) {
    if (!_connection.send(message)) {
      throw const ServerException('Non connesso al server: non inviato');
    }
  }

  @override
  void block(String personId) => _send({'type': 'block', 'personId': personId});

  @override
  void report({required String personId, required ReportReason reason}) =>
      _send({'type': 'report', 'personId': personId, 'reason': reason.name});

  @override
  Stream<SafetyRejectionModel> watchRejections(String sessionId) => _connection
      .connect(sessionId)
      .handleError((Object _) {})
      .expand((decoded) {
        final rejection = SafetyRejectionModel.tryFromJson(decoded);
        return rejection == null ? const <SafetyRejectionModel>[] : [rejection];
      });

  @override
  Future<void> reset() async {}
}
