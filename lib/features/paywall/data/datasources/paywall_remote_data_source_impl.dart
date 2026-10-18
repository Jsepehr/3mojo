import 'dart:convert';

import 'package:http/http.dart' as http;

import '/core/errors/exceptions.dart';
import '/core/network/api_config.dart';
import 'paywall_remote_data_source.dart';

/// Implementazione **reale**: chiama `server/` via HTTP (non serve il
/// push in tempo reale della connessione condivisa — controllare lo
/// sblocco è un'azione puntuale, non qualcosa che cambia da solo mentre
/// la si guarda). Il token viaggia sempre nel corpo, mai nell'URL.
class PaywallRemoteDataSourceImpl implements PaywallRemoteDataSource {
  final http.Client _client = http.Client();

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  @override
  Future<UnlockGrant> purchase() async {
    final http.Response response;
    try {
      response = await _client.post(_uri('/paywall/purchase'));
    } on Exception catch (e) {
      throw ServerException('Server irraggiungibile: $e');
    }
    if (response.statusCode != 200) {
      throw ServerException('Errore nello sblocco (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      token: body['unlockToken'] as String,
      validFor: Duration(seconds: body['expiresInSeconds'] as int),
    );
  }

  @override
  Future<bool> getStatus(String unlockToken) async {
    final http.Response response;
    try {
      response = await _client.post(
        _uri('/paywall/status'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'unlockToken': unlockToken}),
      );
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
