import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/client_ip.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/rate_limiters.dart';

/// `POST /paywall/purchase` — registra un nuovo sblocco con l'ora **del
/// server** e risponde `{"unlockToken": "...", "expiresInSeconds": 7200,
/// "remainingSeconds": 7200}` — `remainingSeconds` (il tempo residuo
/// sull'orologio del server, lo stesso campo di `/paywall/status`) è quello
/// che il client usa; `expiresInSeconds` resta per i client già usciti.
/// Il client manda poi quel token (mai un identificativo del dispositivo)
/// per chiedere lo stato e insieme alla presenza.
///
/// **Finto**: nessun pagamento vero verificato qui, chiunque chiami questa
/// route ottiene uno sblocco (vedi `PurchaseUnlockUseCase` lato client).
/// Con un pagamento reale, il token va emesso solo dopo aver verificato la
/// ricevuta di App Store / Google Play.
///
/// Limitata per IP (`purchaseRateLimiter`, dietro un proxy fidato vedi
/// `TRUSTED_PROXY`): ogni chiamata crea un token in memoria.
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

  final store = PaywallStore.instance;
  final token = store.issueUnlockToken();
  return Response.json(
    body: {
      'unlockToken': token,
      'expiresInSeconds': PaywallStore.unlockDuration.inSeconds,
      'remainingSeconds': store.remainingSecondsFor(token),
    },
  );
}

final Set<String> _trustedProxies = trustedProxiesFromEnvironment();
