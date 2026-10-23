import 'dart:developer' as developer;
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/client_ip.dart';
import 'package:threemojo_server/src/payments/payments.dart';
import 'package:threemojo_server/src/payments/receipt_verifier.dart';
import 'package:threemojo_server/src/payments/unlock_purchase_service.dart';
import 'package:threemojo_server/src/paywall_store.dart';
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

  final clientIp = resolveClientIp(
    remoteAddress: context.request.connectionInfo.remoteAddress.address,
    forwardedFor: context.request.headers['x-forwarded-for'],
    trustedProxies: _trustedProxies,
  );
  if (!purchaseRateLimiter.tryAcquire(clientIp)) {
    return Response.json(
      statusCode: HttpStatus.tooManyRequests,
      body: {'error': 'Troppe richieste, riprova tra qualche minuto'},
    );
  }

  final claim = await _readClaim(context.request);
  if (claim == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Richiesta non valida', 'code': 'invalidRequest'},
    );
  }

  try {
    final grant = await Payments.instance.service.redeem(claim);
    return Response.json(
      body: {
        'unlockToken': grant.unlockToken,
        'expiresInSeconds': PaywallStore.unlockDuration.inSeconds,
        'remainingSeconds': grant.remaining.inSeconds,
        'alreadyRedeemed': grant.replayed,
      },
    );
  } on ReceiptRejectedException catch (e) {
    _log('rifiutata (${claim.platform.name}): ${e.reason.name}');
    return Response.json(
      statusCode: HttpStatus.unprocessableEntity,
      body: {'error': 'Acquisto non valido', 'code': e.reason.name},
    );
  } on PurchaseAlreadyRedeemedException {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'error': 'Acquisto già riscattato', 'code': 'alreadyRedeemed'},
    );
  } on PlatformNotEnabledException {
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {
        'error': 'Pagamenti non attivi per questa piattaforma',
        'code': 'platformNotEnabled',
      },
    );
  } on StoreNotConfiguredException catch (e) {
    _log('configurazione: ${e.detail}');
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {
        'error': 'Pagamenti non configurati',
        'code': 'storeNotConfigured',
      },
    );
  } on StoreUnavailableException catch (e) {
    _log('negozio non raggiungibile: ${e.detail}');
    return Response.json(
      statusCode: HttpStatus.badGateway,
      body: {'error': 'Negozio non raggiungibile', 'code': 'storeUnavailable'},
    );
  }
}

/// `null` se il corpo non è un acquisto ben formato. Nessun campo viene
/// creduto qui: lo verifica il negozio.
Future<PurchaseClaim?> _readClaim(Request request) async {
  final Object? body;
  try {
    body = await request.json();
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

/// Solo l'esito, mai ricevute, token o transazioni.
void _log(String message) =>
    developer.log(message, name: 'paywall.purchase', level: 800);

final Set<String> _trustedProxies = trustedProxiesFromEnvironment();
