import 'dart:convert';

import 'package:http/http.dart' as http;

import '/core/errors/exceptions.dart';
import '/core/network/api_config.dart';
import '../models/store_purchase_model.dart';
import 'paywall_remote_data_source.dart';

/// Implementazione **reale**: chiama `server/` via HTTP (non serve il
/// push in tempo reale della connessione condivisa — controllare lo
/// sblocco è un'azione puntuale, non qualcosa che cambia da solo mentre
/// la si guarda). Il token viaggia sempre nel corpo, mai nell'URL.
class PaywallRemoteDataSourceImpl implements PaywallRemoteDataSource {
  PaywallRemoteDataSourceImpl({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  @override
  Future<UnlockGrant> redeemPurchase(StorePurchaseModel purchase) async {
    final http.Response response;
    try {
      response = await _client.post(
        _uri('/paywall/purchase'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(purchase.toJson()),
      );
    } on Exception catch (e) {
      throw ServerException('Server irraggiungibile: $e');
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 409:
        throw const PurchaseAlreadyRedeemedException();
      case 422:
        final code = _tryDecodeObject(response.body)?['code'];
        throw PurchaseRejectedException(code is String ? code : 'unknown');
      default:
        // 400, 429, 502, 503…: nessun token, l'acquisto resta da riscattare.
        throw ServerException('Errore nello sblocco (${response.statusCode})');
    }

    final body = _decodeObject(response.body);
    final token = body['unlockToken'];
    final seconds = body['remainingSeconds'];
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

  Map<String, dynamic>? _tryDecodeObject(String raw) {
    try {
      return _decodeObject(raw);
    } on ServerException {
      return null;
    }
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
