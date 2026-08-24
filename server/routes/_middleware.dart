import 'package:dart_frog/dart_frog.dart';

/// Il client Flutter web gira su un'origine diversa da questo server
/// (porte diverse, es. `flutter run -d chrome`) — senza CORS il browser
/// blocca tutte le chiamate, anche in locale. Non serve invece per
/// Android/iOS/desktop, che non applicano same-origin policy.
Handler middleware(Handler handler) => handler.use(_cors());

Middleware _cors() {
  return (handler) {
    return (context) async {
      if (context.request.method == HttpMethod.options) {
        return Response(headers: _corsHeaders);
      }

      final response = await handler(context);
      return response.copyWith(headers: {...response.headers, ..._corsHeaders});
    };
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};
