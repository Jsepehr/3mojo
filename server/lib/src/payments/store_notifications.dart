import 'dart:convert';

import 'apple_jws_verifier.dart';
import 'payments_config.dart';
import 'receipt_verifier.dart';
import 'unlock_purchase_service.dart';

/// Esito di una notifica server-to-server.
enum NotificationOutcome {
  /// Valida e gestita: lo sblocco della transazione è stato revocato.
  revoked,

  /// Valida ma non ci riguarda (tipo diverso, transazione senza sblocco
  /// attivo, notifica di prova): si risponde comunque 200, sennò il negozio
  /// la rimanda.
  ignored,

  /// Non autentica o malformata: 400, nulla cambia.
  invalid,
}

/// **App Store Server Notifications v2** (`POST
/// /paywall/notifications/apple`, spenta finché
/// `APPLE_NOTIFICATIONS_ENABLED=true`). Corpo `{"signedPayload": JWS}`,
/// verificato come le transazioni (`AppleJwsVerifier`); dentro,
/// `data.signedTransactionInfo` è a sua volta un JWS.
///
/// Su `REFUND` e `REVOKE` revoca subito lo sblocco nato da quella
/// transazione (`UnlockPurchaseService.revokeTransaction`): il registro
/// tiene la corrispondenza hash della transazione → token proprio per
/// questo, e **solo finché il token vale** (2 ore). Dopo non resta nulla
/// da revocare: lo sblocco è già finito da solo.
///
/// URL da impostare in App Store Connect → App → Informazioni sull'app →
/// "Notifiche del server App Store" (versione 2), sia produzione sia
/// sandbox.
class AppleNotificationHandler {
  AppleNotificationHandler({
    required AppleStoreSettings settings,
    required UnlockPurchaseService service,
    AppleJwsVerifier? jwsVerifier,
  }) : _settings = settings,
       _service = service,
       _jwsVerifier =
           jwsVerifier ?? AppleJwsVerifier(trustedRoots: settings.trustedRoots);

  static const revokingTypes = {'REFUND', 'REVOKE'};

  final AppleStoreSettings _settings;
  final UnlockPurchaseService _service;
  final AppleJwsVerifier _jwsVerifier;

  Future<NotificationOutcome> handle(Object? body) async {
    if (body is! Map || body['signedPayload'] is! String) {
      return NotificationOutcome.invalid;
    }
    final Map<String, dynamic> payload;
    try {
      payload = _jwsVerifier.verify(body['signedPayload'] as String);
    } on ReceiptRejectedException {
      return NotificationOutcome.invalid;
    }
    final data = payload['data'];
    if (data is! Map) return NotificationOutcome.ignored;
    if (data['bundleId'] != _settings.bundleId ||
        !_settings.acceptedEnvironments.contains(data['environment'])) {
      return NotificationOutcome.invalid;
    }
    if (!revokingTypes.contains(payload['notificationType'])) {
      return NotificationOutcome.ignored;
    }
    final signedTransaction = data['signedTransactionInfo'];
    if (signedTransaction is! String) return NotificationOutcome.invalid;
    final Map<String, dynamic> transaction;
    try {
      transaction = _jwsVerifier.verify(signedTransaction);
    } on ReceiptRejectedException {
      return NotificationOutcome.invalid;
    }
    final transactionId = transaction['transactionId'];
    if (transactionId is! String ||
        transaction['bundleId'] != _settings.bundleId) {
      return NotificationOutcome.invalid;
    }
    final revoked = await _service.revokeTransaction(
      StorePlatform.ios,
      transactionId,
    );
    return revoked ? NotificationOutcome.revoked : NotificationOutcome.ignored;
  }
}

/// **Google Play Real-time Developer Notifications** via Pub/Sub push
/// (`POST /paywall/notifications/google?token=…`, spenta finché manca
/// `GOOGLE_RTDN_TOKEN`). Corpo `{"message": {"data": base64(JSON)}}`.
///
/// Su `voidedPurchaseNotification` (rimborso, chargeback, annullamento di
/// un acquisto) e su `oneTimeProductNotification` di tipo 2
/// (`ONE_TIME_PRODUCT_CANCELED`) revoca lo sblocco nato da quel
/// `purchaseToken`.
///
/// Autenticazione: il segreto `token` nell'URL di push (confronto a tempo
/// costante nella route). Le notifiche Google non sono firmate nel corpo.
/// TODO(produzione): in alternativa al segreto nell'URL, abilitare
/// l'autenticazione OIDC della sottoscrizione push e verificare il JWT
/// `Authorization: Bearer` di Google (audience = URL della route).
class GoogleNotificationHandler {
  GoogleNotificationHandler({
    required GooglePlaySettings settings,
    required UnlockPurchaseService service,
  }) : _settings = settings,
       _service = service;

  final GooglePlaySettings _settings;
  final UnlockPurchaseService _service;

  Future<NotificationOutcome> handle(Object? body) async {
    final message = body is Map ? body['message'] : null;
    final rawData = message is Map ? message['data'] : null;
    if (rawData is! String) return NotificationOutcome.invalid;
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(base64.decode(base64.normalize(rawData))));
    } on FormatException {
      return NotificationOutcome.invalid;
    }
    if (data is! Map) return NotificationOutcome.invalid;
    if (data['packageName'] != _settings.packageName) {
      return NotificationOutcome.invalid;
    }

    Object? purchaseToken;
    final voided = data['voidedPurchaseNotification'];
    final oneTime = data['oneTimeProductNotification'];
    if (voided is Map) {
      purchaseToken = voided['purchaseToken'];
    } else if (oneTime is Map && oneTime['notificationType'] == 2) {
      purchaseToken = oneTime['purchaseToken'];
    }
    if (purchaseToken is! String || purchaseToken.isEmpty) {
      return NotificationOutcome.ignored;
    }
    final revoked = await _service.revokeTransaction(
      StorePlatform.android,
      purchaseToken,
    );
    return revoked ? NotificationOutcome.revoked : NotificationOutcome.ignored;
  }
}
