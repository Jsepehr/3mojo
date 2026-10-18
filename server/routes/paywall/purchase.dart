import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/paywall_store.dart';

/// `POST /paywall/purchase` — registra un nuovo sblocco con l'ora **del
/// server** e risponde `{"unlockToken": "...", "expiresInSeconds": 7200}`.
/// Il client manda poi quel token (mai un identificativo del dispositivo)
/// per chiedere lo stato e insieme alla presenza.
///
/// **Finto**: nessun pagamento vero verificato qui, chiunque chiami questa
/// route ottiene uno sblocco (vedi `PurchaseUnlockUseCase` lato client).
/// Con un pagamento reale, il token va emesso solo dopo aver verificato la
/// ricevuta di App Store / Google Play.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final token = PaywallStore.instance.issueUnlockToken();
  return Response.json(
    body: {
      'unlockToken': token,
      'expiresInSeconds': PaywallStore.unlockDuration.inSeconds,
    },
  );
}
