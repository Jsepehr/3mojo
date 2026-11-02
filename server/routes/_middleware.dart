import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/cors_policy.dart';

/// Il client Flutter web gira su un'origine diversa da questo server
/// (porte diverse, es. `flutter run -d chrome`) — senza CORS il browser
/// blocca tutte le chiamate, anche in locale. Non serve invece per
/// Android/iOS/desktop, che non applicano same-origin policy: per questo in
/// production (`RAEN_ENV=production`) gli header CORS non ci sono, salvo
/// `CORS_ALLOW_ORIGIN` (vedi `CorsPolicy`).
Handler middleware(Handler handler) => handler.use(_cors());

Middleware _cors() {
  return (handler) {
    return (context) async {
      final headers = CorsPolicy.instance.headersFor(
        context.request.headers['origin'],
      );
      if (context.request.method == HttpMethod.options) {
        return Response(headers: headers);
      }

      final response = await handler(context);
      if (headers.isEmpty) return response;
      return response.copyWith(headers: {...response.headers, ...headers});
    };
  };
}
