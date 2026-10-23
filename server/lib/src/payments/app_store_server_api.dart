import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ecdsa.dart';
import 'payments_config.dart';
import 'receipt_verifier.dart';

/// Il pezzo dell'**App Store Server API** che serve qui: "Get Transaction
/// Info" (`GET /inApps/v1/transactions/{transactionId}`), che risponde con
/// la transazione firmata (`signedTransactionInfo`, da verificare con
/// `AppleJwsVerifier` come quella mandata dall'app).
///
/// Serve quando l'app non manda il JWS (StoreKit 1) o per ricontrollare
/// una transazione. Autenticazione: JWT ES256 firmato con la chiave `.p8`
/// di App Store Connect (`APPLE_KEY_ID`, `APPLE_ISSUER_ID`), valido 5
/// minuti, rifatto a ogni chiamata.
///
/// In produzione chiede prima all'ambiente di produzione e, se la
/// transazione non c'è (404), a quello sandbox (gli acquisti di App
/// Review), come raccomanda Apple.
class AppStoreServerApi {
  AppStoreServerApi({
    required AppleApiCredentials credentials,
    required this.bundleId,
    required this.environment,
    http.Client? client,
    DateTime Function()? now,
  }) : _credentials = credentials,
       _key = EcPrivateKey.fromPkcs8Pem(credentials.privateKeyPem),
       _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  static final productionBaseUrl = Uri.parse(
    'https://api.storekit.itunes.apple.com',
  );
  static final sandboxBaseUrl = Uri.parse(
    'https://api.storekit-sandbox.itunes.apple.com',
  );

  final AppleApiCredentials _credentials;
  final EcPrivateKey _key;
  final String bundleId;
  final AppleEnvironment environment;
  final http.Client _client;
  final DateTime Function() _now;

  /// La transazione firmata (JWS) con quell'id. Lancia
  /// [ReceiptRejectedException] se Apple non la conosce,
  /// [StoreNotConfiguredException] se rifiuta le credenziali,
  /// [StoreUnavailableException] per errori temporanei.
  Future<String> getSignedTransaction(String transactionId) async {
    if (!RegExp(r'^[0-9]{1,32}$').hasMatch(transactionId)) {
      throw const ReceiptRejectedException(
        ReceiptRejection.invalidReceipt,
        'transactionId non numerico',
      );
    }
    final bases = environment == AppleEnvironment.production
        ? [productionBaseUrl, sandboxBaseUrl]
        : [sandboxBaseUrl];
    for (final base in bases) {
      final jws = await _get(base, transactionId);
      if (jws != null) return jws;
    }
    throw const ReceiptRejectedException(
      ReceiptRejection.invalidReceipt,
      'transazione sconosciuta ad Apple',
    );
  }

  /// `null` se Apple risponde 404 in quell'ambiente.
  Future<String?> _get(Uri base, String transactionId) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            base.resolve('/inApps/v1/transactions/$transactionId'),
            headers: {'Authorization': 'Bearer ${buildToken()}'},
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw StoreUnavailableException('App Store Server API: $e');
    }
    switch (response.statusCode) {
      case 200:
        final Object? body;
        try {
          body = jsonDecode(response.body);
        } on FormatException {
          throw const StoreUnavailableException('risposta Apple non JSON');
        }
        final jws = body is Map ? body['signedTransactionInfo'] : null;
        if (jws is! String) {
          throw const StoreUnavailableException(
            'risposta Apple senza signedTransactionInfo',
          );
        }
        return jws;
      case 404:
        return null;
      case 400:
        throw const ReceiptRejectedException(
          ReceiptRejection.invalidReceipt,
          'Apple: transactionId non valido',
        );
      case 401:
        throw const StoreNotConfiguredException(
          'Apple rifiuta le credenziali (APPLE_ISSUER_ID/APPLE_KEY_ID/chiave)',
        );
      default:
        throw StoreUnavailableException('Apple: HTTP ${response.statusCode}');
    }
  }

  /// Il JWT per l'header `Authorization` (pubblico per i test).
  String buildToken() {
    final issuedAt = _now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final header = _encode({
      'alg': 'ES256',
      'kid': _credentials.keyId,
      'typ': 'JWT',
    });
    final payload = _encode({
      'iss': _credentials.issuerId,
      'iat': issuedAt,
      'exp': issuedAt + 300,
      'aud': 'appstoreconnect-v1',
      'bid': bundleId,
    });
    final signed = '$header.$payload';
    final signature = _key.signEs256(Uint8List.fromList(ascii.encode(signed)));
    return '$signed.${_base64Url(signature)}';
  }

  static String _encode(Map<String, Object> json) =>
      _base64Url(utf8.encode(jsonEncode(json)));

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
