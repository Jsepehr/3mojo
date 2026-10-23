import 'dart:async';
import 'dart:convert';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'receipt_verifier.dart';

/// Le due chiamate della **Google Play Developer API** (`androidpublisher`
/// v3) che servono per un prodotto consumabile.
abstract class GooglePlayApi {
  /// `purchases.products.get`: la `ProductPurchase` così com'è per Google.
  Future<Map<String, dynamic>> getProductPurchase({
    required String productId,
    required String purchaseToken,
  });

  /// `purchases.products.consume`: dopo il consumo l'acquisto non torna
  /// più "da consumare" (e l'utente può ricomprare lo sblocco).
  Future<void> consume({
    required String productId,
    required String purchaseToken,
  });
}

/// Implementazione via HTTP con il service account
/// (`GOOGLE_SERVICE_ACCOUNT_JSON_PATH`, `googleapis_auth`: token OAuth2
/// rinnovato da solo). Il service account va invitato in Play Console con
/// il permesso "Visualizza dati finanziari e gestisci ordini".
///
/// Errori: 400/404/410 → ricevuta non valida; 401/403 → credenziali o
/// permessi sbagliati (503); il resto → temporaneo (502, si riprova).
class GooglePlayApiImpl implements GooglePlayApi {
  GooglePlayApiImpl({
    required this.packageName,
    required String serviceAccountJson,
    Future<http.Client> Function()? clientFactory,
  }) : _clientFactory =
           clientFactory ??
           (() => clientViaServiceAccount(
             ServiceAccountCredentials.fromJson(serviceAccountJson),
             const ['https://www.googleapis.com/auth/androidpublisher'],
           ));

  final String packageName;
  final Future<http.Client> Function() _clientFactory;
  Future<http.Client>? _client;

  Uri _uri(String productId, String purchaseToken, [String action = '']) => Uri(
    scheme: 'https',
    host: 'androidpublisher.googleapis.com',
    pathSegments: [
      'androidpublisher',
      'v3',
      'applications',
      packageName,
      'purchases',
      'products',
      productId,
      'tokens',
      '$purchaseToken$action',
    ],
  );

  Future<http.Client> _authorized() async {
    try {
      return await (_client ??= _clientFactory());
    } catch (e) {
      _client = null;
      throw StoreNotConfiguredException('service account Google: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> getProductPurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    final client = await _authorized();
    final response = await _send(
      () => client.get(_uri(productId, purchaseToken)),
    );
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw const StoreUnavailableException('risposta Google non JSON');
    }
    if (body is! Map<String, dynamic>) {
      throw const StoreUnavailableException('risposta Google non valida');
    }
    return body;
  }

  @override
  Future<void> consume({
    required String productId,
    required String purchaseToken,
  }) async {
    final client = await _authorized();
    await _send(() => client.post(_uri(productId, purchaseToken, ':consume')));
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    final http.Response response;
    try {
      response = await call().timeout(const Duration(seconds: 10));
    } catch (e) {
      throw StoreUnavailableException('Google Play Developer API: $e');
    }
    final status = response.statusCode;
    if (status >= 200 && status < 300) return response;
    if (status == 400 || status == 404 || status == 410) {
      throw ReceiptRejectedException(
        ReceiptRejection.invalidReceipt,
        'Google: HTTP $status',
      );
    }
    if (status == 401 || status == 403) {
      throw StoreNotConfiguredException(
        'Google rifiuta il service account (HTTP $status): permessi in Play '
        'Console?',
      );
    }
    throw StoreUnavailableException('Google: HTTP $status');
  }
}
