import 'dart:convert';
import 'dart:typed_data';

import '/core/network/realtime_connection.dart';
import '/features/nearby/data/models/nearby_person_model.dart';
import 'nearby_remote_data_source.dart';

/// Implementazione **reale**: usa la connessione WebSocket condivisa
/// (`RealtimeConnection`, in `core/network/`) verso il backend `server/`
/// (dart_frog) in esecuzione in locale — nessuna simulazione, chi vedi qui
/// è chi ha davvero mandato una posizione al server in questo momento.
class NearbyRemoteDataSourceImpl implements NearbyRemoteDataSource {
  // Il profilo mandato al connect, riusato a ogni updatePosition — sulla
  // connessione persistente non serve rimandarlo per intero ogni volta,
  // solo la posizione cambia.
  String _gender = 'unspecified';
  String _genderPreference = 'everyone';
  String _selfieBase64 = '';

  @override
  Stream<List<NearbyPersonModel>> connect({
    required String sessionId,
    required double latitude,
    required double longitude,
    required String gender,
    required String genderPreference,
    required Uint8List selfieBytes,
  }) {
    _gender = gender;
    _genderPreference = genderPreference;
    _selfieBase64 = selfieBytes.isEmpty ? '' : base64Encode(selfieBytes);

    final messages = RealtimeConnection.instance.connect(sessionId);
    updatePosition(latitude: latitude, longitude: longitude);

    return messages.expand((decoded) {
      if (decoded['type'] != 'nearby') return const <List<NearbyPersonModel>>[];

      final people = decoded['people'] as List<dynamic>;
      return [
        people
            .map(
              (json) => NearbyPersonModel.fromJson(json as Map<String, dynamic>),
            )
            .toList(),
      ];
    });
  }

  @override
  void updatePosition({required double latitude, required double longitude}) {
    RealtimeConnection.instance.send({
      'type': 'presence',
      'lat': latitude,
      'lng': longitude,
      'gender': _gender,
      'genderPreference': _genderPreference,
      'selfieBase64': _selfieBase64,
    });
  }

  @override
  Future<void> disconnect() => RealtimeConnection.instance.disconnect();
}
