import 'dart:async';
import 'dart:convert';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'attestation_verifier.dart';

/// La chiamata della **Play Integrity API** che serve: `decodeIntegrityToken`
/// — Google decifra e verifica il token prodotto sul telefono e risponde
/// col verdetto in chiaro (`tokenPayloadExternal`).
abstract class PlayIntegrityApi {
  /// Il `tokenPayloadExternal` del token, così come lo dà Google.
  Future<Map<String, dynamic>> decodeIntegrityToken(String token);
}

/// Implementazione via HTTP con un service account (`googleapis_auth`:
/// token OAuth2 rinnovato da solo), scope `playintegrity`:
/// `POST https://playintegrity.googleapis.com/v1/{packageName}:decodeIntegrityToken`.
///
/// Il service account deve stare nel **progetto Google Cloud collegato
/// all'app in Play Console** (Play Console → Test e rilascio → Integrità
/// dell'app), con la Play Integrity API abilitata in quel progetto: Google
/// decodifica i token solo per il progetto collegato. Può essere lo stesso
/// service account dei pagamenti (`GOOGLE_SERVICE_ACCOUNT_JSON_PATH`).
///
/// Errori: 400 → token non valido (rifiuto); 401/403 → credenziali o
/// progetto sbagliati; 429 → quota giornaliera finita; il resto → Google
/// non disponibile. Tutto ciò che non è un rifiuto è
/// [AttestationUnavailableException].
class PlayIntegrityApiImpl implements PlayIntegrityApi {
  PlayIntegrityApiImpl({
    required this.packageName,
    required String serviceAccountJson,
    Future<http.Client> Function()? clientFactory,
    this.timeout = const Duration(seconds: 8),
  }) : _clientFactory =
           clientFactory ??
           (() => clientViaServiceAccount(
             ServiceAccountCredentials.fromJson(serviceAccountJson),
             const ['https://www.googleapis.com/auth/playintegrity'],
           ));

  final String packageName;
  final Duration timeout;
  final Future<http.Client> Function() _clientFactory;
  Future<http.Client>? _client;

  Uri get _uri => Uri(
    scheme: 'https',
    host: 'playintegrity.googleapis.com',
    pathSegments: ['v1', '$packageName:decodeIntegrityToken'],
  );

  Future<http.Client> _authorized() async {
    try {
      return await (_client ??= _clientFactory());
    } catch (e) {
      _client = null;
      throw AttestationUnavailableException('service account Google: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> decodeIntegrityToken(String token) async {
    final client = await _authorized();
    final http.Response response;
    try {
      response = await client
          .post(
            _uri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'integrityToken': token}),
          )
          .timeout(timeout);
    } catch (e) {
      throw AttestationUnavailableException('Play Integrity API: $e');
    }
    final status = response.statusCode;
    if (status == 400) {
      throw const AttestationRejectedException(
        AttestationRejection.malformed,
        'Google: HTTP 400',
      );
    }
    if (status < 200 || status >= 300) {
      throw AttestationUnavailableException(
        status == 401 || status == 403
            ? 'Google rifiuta il service account (HTTP $status): progetto '
                  'collegato in Play Console e API abilitata?'
            : status == 429
            ? 'quota della Play Integrity API esaurita (HTTP 429)'
            : 'Google: HTTP $status',
      );
    }
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw const AttestationUnavailableException('risposta Google non JSON');
    }
    final payload = body is Map<String, dynamic>
        ? body['tokenPayloadExternal']
        : null;
    if (payload is! Map<String, dynamic>) {
      throw const AttestationUnavailableException(
        'risposta Google senza tokenPayloadExternal',
      );
    }
    return payload;
  }
}
