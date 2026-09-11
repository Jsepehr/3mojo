import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '/core/device/device_id_provider.dart';
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

  // `deviceId` (core/device/, condiviso con `paywall/`) non è disponibile in
  // modo sincrono al connect -- arriva un istante dopo, via
  // `_attachDeviceId`. Fino ad allora resta vuoto: il server tratta una
  // sessione senza deviceId collegato come "non sbloccata" (fallback
  // sicuro), mai come un errore. `_lastLatitude`/`_lastLongitude` servono
  // solo a rimandare la presenza una seconda volta non appena il deviceId
  // è pronto, senza dover aspettare il prossimo vero aggiornamento di
  // posizione.
  String _deviceId = '';
  double _lastLatitude = 0;
  double _lastLongitude = 0;

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
    unawaited(_attachDeviceId());

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

  Future<void> _attachDeviceId() async {
    _deviceId = await DeviceIdProvider.instance.getOrCreateDeviceId();
    updatePosition(latitude: _lastLatitude, longitude: _lastLongitude);
  }

  @override
  void updatePosition({required double latitude, required double longitude}) {
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    RealtimeConnection.instance.send({
      'type': 'presence',
      'lat': latitude,
      'lng': longitude,
      'gender': _gender,
      'genderPreference': _genderPreference,
      'selfieBase64': _selfieBase64,
      'deviceId': _deviceId,
    });
  }

  @override
  Future<void> disconnect() => RealtimeConnection.instance.disconnect();
}
