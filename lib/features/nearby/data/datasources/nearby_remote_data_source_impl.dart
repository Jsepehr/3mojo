import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '/core/network/realtime_connection.dart';
import '/core/unlock/unlock_token_store.dart';
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

  // Il token di sblocco a pagamento (core/unlock/, condiviso con
  // `paywall/`), solo se si è pagato: chi non paga non manda nulla che lo
  // identifichi. Si legge in modo asincrono un istante dopo il connect
  // (`_attachUnlockToken`) e si aggiorna da solo dopo un acquisto a sessione
  // già avviata (`UnlockTokenStore.changes`): in entrambi i casi la
  // presenza viene rimandata subito, senza aspettare il prossimo vero
  // aggiornamento di posizione — `_lastLatitude`/`_lastLongitude` servono
  // solo a questo. Finché non c'è, il server tratta la sessione come "non
  // sbloccata", mai come un errore.
  String? _unlockToken;
  StreamSubscription<String?>? _unlockTokenChanges;
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
    unawaited(_attachUnlockToken());

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

  Future<void> _attachUnlockToken() async {
    await _unlockTokenChanges?.cancel();
    _unlockTokenChanges = UnlockTokenStore.instance.changes.listen((token) {
      _unlockToken = token;
      updatePosition(latitude: _lastLatitude, longitude: _lastLongitude);
    });
    final token = await UnlockTokenStore.instance.read();
    if (token == null) return;
    _unlockToken = token;
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
      if (_unlockToken != null) 'unlockToken': _unlockToken,
    });
  }

  @override
  Future<void> disconnect() async {
    await _unlockTokenChanges?.cancel();
    _unlockTokenChanges = null;
    await RealtimeConnection.instance.disconnect();
  }
}
