import 'dart:convert';

import 'package:http/http.dart' as http;

import '/core/errors/exceptions.dart';
import '/core/network/api_config.dart';
import '/features/nearby/data/models/nearby_person_model.dart';
import 'nearby_remote_data_source.dart';

/// Implementazione **reale**: parla con il backend `server/` (dart_frog) in
/// esecuzione in locale — nessuna simulazione, chi vedi qui è chi ha
/// davvero mandato una posizione al server in questo momento.
class NearbyRemoteDataSourceImpl implements NearbyRemoteDataSource {
  final http.Client _client = http.Client();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  @override
  Future<List<NearbyPersonModel>> reportPresenceAndFetchNearbyPeople({
    required String sessionId,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required String gender,
    required String genderPreference,
    required String selfieBase64,
  }) async {
    final presenceResponse = await _post(
      _uri('/presence'),
      body: {
        'sessionId': sessionId,
        'lat': latitude,
        'lng': longitude,
        'gender': gender,
        'genderPreference': genderPreference,
        'selfieBase64': selfieBase64,
      },
    );
    if (presenceResponse.statusCode != 204) {
      throw ServerException(
        'Errore nel mandare la posizione (${presenceResponse.statusCode})',
      );
    }

    final nearbyResponse = await _get(
      _uri('/nearby', {
        'sessionId': sessionId,
        'radiusMeters': radiusMeters.toString(),
      }),
    );
    if (nearbyResponse.statusCode != 200) {
      throw ServerException(
        'Errore nel leggere le persone vicine (${nearbyResponse.statusCode})',
      );
    }

    final body = jsonDecode(nearbyResponse.body) as List<dynamic>;
    return body
        .map((json) => NearbyPersonModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> removePresence(String sessionId) async {
    final http.Response response;
    try {
      response = await _client.delete(
        _uri('/presence', {'sessionId': sessionId}),
      );
    } on Exception catch (e) {
      throw ServerException('Server irraggiungibile: $e');
    }
    if (response.statusCode != 204) {
      throw ServerException(
        'Errore nel segnalare la mia uscita (${response.statusCode})',
      );
    }
  }

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, dynamic> body,
  }) async {
    try {
      return await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } on Exception catch (e) {
      throw ServerException('Server irraggiungibile: $e');
    }
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri);
    } on Exception catch (e) {
      throw ServerException('Server irraggiungibile: $e');
    }
  }
}
