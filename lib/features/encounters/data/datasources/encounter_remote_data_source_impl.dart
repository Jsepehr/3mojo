import '/core/network/realtime_connection.dart';
import '../models/encounter_request_model.dart';
import 'encounter_remote_data_source.dart';

/// Implementazione **reale**: usa la connessione WebSocket condivisa
/// (`RealtimeConnection`, la stessa di `nearby`) verso il backend `server/`
/// — nessuna simulazione, chi vedi qui è chi ha davvero mandato/ricevuto
/// una richiesta su questa sessione.
class EncounterRemoteDataSourceImpl implements EncounterRemoteDataSource {
  @override
  Stream<({List<EncounterRequestModel> incoming, List<EncounterRequestModel> outgoing})>
  watchRequests(String sessionId) {
    final messages = RealtimeConnection.instance.connect(sessionId);

    return messages
        .where((decoded) => decoded['type'] == 'encounters')
        .map((decoded) {
          List<EncounterRequestModel> parse(String key) =>
              (decoded[key] as List<dynamic>)
                  .map(
                    (json) => EncounterRequestModel.fromJson(
                      json as Map<String, dynamic>,
                    ),
                  )
                  .toList();

          return (incoming: parse('incoming'), outgoing: parse('outgoing'));
        });
  }

  @override
  void sendRequest({required String otherPersonId}) {
    RealtimeConnection.instance.send({
      'type': 'sendEncounterRequest',
      'toSessionId': otherPersonId,
    });
  }

  @override
  void respondToRequest({required String requestId, required bool accepted}) {
    RealtimeConnection.instance.send({
      'type': 'respondToEncounterRequest',
      'requestId': requestId,
      'accepted': accepted,
    });
  }

  @override
  void endMatch(String requestId) {
    RealtimeConnection.instance.send({'type': 'endMatch', 'requestId': requestId});
  }
}
