import 'dart:convert';

import 'package:http/http.dart' as http;

import '/core/errors/exceptions.dart';
import '/core/network/api_config.dart';
import 'paywall_remote_data_source.dart';

/// Implementazione **reale**: chiama `server/` via HTTP (non serve il
/// push in tempo reale della connessione condivisa — controllare lo
/// sblocco è un'azione puntuale, non qualcosa che cambia da solo mentre
/// la si guarda).
class PaywallRemoteDataSourceImpl implements PaywallRemoteDataSource {
  final http.Client _client = http.Client();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  @override
  Future<void> purchase(String deviceId) async {
    final http.Response response;
    try {
      response = await _client.post(
        _uri('/paywall/purchase'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'deviceId': deviceId}),
      );
    } on Exception catch (e) {
      throw ServerException('Server irraggiungibile: $e');
    }
    if (response.statusCode != 204) {
      throw ServerException('Errore nello sblocco (${response.statusCode})');
    }
  }

  @override
  Future<bool> getStatus(String deviceId) async {
    final http.Response response;
    try {
      response = await _client.get(_uri('/paywall/status', {'deviceId': deviceId}));
    } on Exception catch (e) {
      throw ServerException('Server irraggiungibile: $e');
    }
    if (response.statusCode != 200) {
      throw ServerException(
        'Errore nel controllo dello sblocco (${response.statusCode})',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['isUnlocked'] as bool;
  }
}
