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

    final body = _decodeObject(response.body);
    final token = body['unlockToken'];
    // `remainingSeconds` è il residuo sull'orologio del server;
    // `expiresInSeconds` è lo stesso numero da server più vecchi.
    final seconds = body['remainingSeconds'] ?? body['expiresInSeconds'];
    if (token is! String || token.isEmpty || seconds is! int) {
      throw const ServerException('Risposta di sblocco non valida');
    }
    return (token: token, remaining: Duration(seconds: seconds));
  }

  @override
  Future<Duration> getRemaining(String unlockToken) async {
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

    final body = _decodeObject(response.body);
    final seconds = body['remainingSeconds'];
    if (seconds is int) {
      return Duration(seconds: seconds < 0 ? 0 : seconds);
    }
    // Server senza `remainingSeconds`: "bloccato" si può ancora credere, uno
    // "sbloccato" senza sapere fino a quando no — meglio un controllo fallito
    // (non cambia nulla, si riprova) che una scadenza inventata.
    if (body['isUnlocked'] == false) return Duration.zero;
    throw const ServerException('Stato dello sblocco senza remainingSeconds');
  }

  Map<String, dynamic> _decodeObject(String raw) {
    final Object? body;
    try {
      body = jsonDecode(raw);
    } on FormatException catch (e) {
      throw ServerException('Risposta non valida: $e');
    }
    if (body is! Map<String, dynamic>) {
      throw const ServerException('Risposta non valida');
    }
    return body;
  }
}
