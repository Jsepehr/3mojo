import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/client_ip.dart';
import 'package:threemojo_server/src/http_limits.dart';
import 'package:threemojo_server/src/log.dart';
import 'package:threemojo_server/src/metrics.dart';
import 'package:threemojo_server/src/payments/payments.dart';
import 'package:threemojo_server/src/payments/receipt_verifier.dart';
import 'package:threemojo_server/src/payments/unlock_purchase_service.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/protocol_version.dart';
import 'package:threemojo_server/src/rate_limiters.dart';

/// `POST /paywall/purchase` — riscatta un acquisto in-app **verificato col
/// negozio** e risponde con il token di sblocco (2 ore, orologio del
/// server).
///
/// Corpo:
/// ```json
/// {"platform": "ios" | "android" | "fake",
///  "productId": "...",
///  "receipt": "...",          // iOS: JWS della transazione (StoreKit 2)
///                             // Android: purchaseToken
///                             // fake: ricevuta del negozio simulato
///  "transactionId": "..."}    // iOS transactionId, Android orderId
/// ```
/// (`purchaseToken` è accettato come sinonimo di `receipt`.)
///
/// Risposte:
/// - 200 `{"unlockToken", "expiresInSeconds", "remainingSeconds",
///   "alreadyRedeemed"}` — `alreadyRedeemed: true` se la transazione era già
///   stata riscattata e il token è lo stesso di allora (nuovo tentativo dopo
///   una risposta persa: l'app completa l'acquisto e basta);
/// - 400 `{"error", "code": "invalidRequest"}`;
/// - 409 `{"code": "alreadyRedeemed"}` — già riscattata, sblocco finito;
/// - 422 `{"code": <ReceiptRejection>}` — il negozio dice che non vale
///   (`invalidReceipt`, `wrongProduct`, `wrongApp`, `wrongEnvironment`,
///   `notPurchased`, `refunded`, `tooOld`, `transactionMismatch`);
/// - 413 `{"code": "bodyTooLarge"}` — corpo oltre 64 KB;
/// - 426 `{"code": "updateRequired"}` — l'header `X-Raen-Protocol` dichiara
///   un protocollo troppo vecchio (`ProtocolPolicy`);
/// - 429 troppe richieste dallo stesso IP;
/// - 502 `{"code": "storeUnavailable"}` — il negozio non risponde, riprovare;
/// - 503 `{"code": "platformNotEnabled" | "storeNotConfigured"}` — il server
///   non accetta pagamenti da questa piattaforma in questa modalità
///   (`PAYMENTS_MODE`, credenziali).
///
/// In ogni caso diverso da 200 **nessun token** viene emesso: l'app non
/// completa l'acquisto nel negozio e può riprovare.
///
/// Limitata per IP (`purchaseRateLimiter`, dietro un proxy fidato vedi
/// `TRUSTED_PROXY`).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final outdated = ProtocolPolicy.instance.checkHttp(context.request.headers);
  if (outdated != null) {
    Metrics.instance.purchase('refusedUpdateRequired');
    return outdated;
  }

  final clientIp = resolveClientIp(
    remoteAddress: context.request.connectionInfo.remoteAddress.address,
    forwardedFor: context.request.headers['x-forwarded-for'],
    trustedProxies: _trustedProxies,
  );
  if (!purchaseRateLimiter.tryAcquire(clientIp)) {
    Metrics.instance.purchase('rateLimited');
    return Response.json(
      statusCode: HttpStatus.tooManyRequests,
      body: {'error': 'Troppe richieste, riprova tra qualche minuto'},
    );
  }

  final PurchaseClaim? claim;
  try {
    claim = await _readClaim(context.request);
  } on BodyTooLargeException {
    Metrics.instance.purchase('bodyTooLarge');
    return bodyTooLargeResponse();
  }
  if (claim == null) {
    Metrics.instance.purchase('invalidRequest');
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Richiesta non valida', 'code': 'invalidRequest'},
    );
  }

  try {
    final grant = await Payments.instance.service.redeem(claim);
    Metrics.instance.purchase(grant.replayed ? 'replayed' : 'granted');
    return Response.json(
      body: {
        'unlockToken': grant.unlockToken,
        'expiresInSeconds': PaywallStore.unlockDuration.inSeconds,
        'remainingSeconds': grant.remaining.inSeconds,
        'alreadyRedeemed': grant.replayed,
      },
    );
  } on ReceiptRejectedException catch (e) {
    Metrics.instance.purchase('rejected_${e.reason.name}');
    Log.info('payments.rejected', {
      'platform': claim.platform.name,
      'reason': e.reason.name,
    });
    return Response.json(
      statusCode: HttpStatus.unprocessableEntity,
      body: {'error': 'Acquisto non valido', 'code': e.reason.name},
    );
  } on PurchaseAlreadyRedeemedException {
    Metrics.instance.purchase('alreadyRedeemed');
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'error': 'Acquisto già riscattato', 'code': 'alreadyRedeemed'},
    );
  } on PlatformNotEnabledException {
    Metrics.instance.purchase('platformNotEnabled');
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {
        'error': 'Pagamenti non attivi per questa piattaforma',
        'code': 'platformNotEnabled',
      },
    );
  } on StoreNotConfiguredException {
    Metrics.instance.purchase('storeNotConfigured');
    Log.error('payments.store_not_configured');
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {
        'error': 'Pagamenti non configurati',
        'code': 'storeNotConfigured',
      },
    );
  } on StoreUnavailableException {
    Metrics.instance.purchase('storeUnavailable');
    Log.warn('payments.store_unavailable');
    return Response.json(
      statusCode: HttpStatus.badGateway,
      body: {'error': 'Negozio non raggiungibile', 'code': 'storeUnavailable'},
    );
  }
}

/// `null` se il corpo non è un acquisto ben formato; lancia
/// [BodyTooLargeException] oltre 64 KB. Nessun campo viene creduto qui: lo
/// verifica il negozio.
Future<PurchaseClaim?> _readClaim(Request request) async {
  final Object? body;
  try {
    body = await readJsonBody(request);
  } on BodyTooLargeException {
    rethrow;
  } catch (_) {
    return null;
  }
  if (body is! Map<String, dynamic>) return null;
  final platform = StorePlatform.fromWire(body['platform']);
  final productId = body['productId'];
  final receipt = body['receipt'] ?? body['purchaseToken'];
  final transactionId = body['transactionId'] ?? '';
  if (platform == null ||
      productId is! String ||
      productId.isEmpty ||
      productId.length > 200 ||
      receipt is! String ||
      receipt.isEmpty ||
      receipt.length > 16 * 1024 ||
      transactionId is! String ||
      transactionId.length > 200) {
    return null;
  }
  return PurchaseClaim(
    platform: platform,
    productId: productId,
    receipt: receipt,
    transactionId: transactionId,
  );
}

final Set<String> _trustedProxies = trustedProxiesFromEnvironment();
