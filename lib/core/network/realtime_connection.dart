import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';

/// Un'unica connessione WebSocket persistente per sessione (`GET /ws`),
/// condivisa tra le feature che ne hanno bisogno — oggi `nearby`
/// (presenza/vicinanze) ed `encounters` (richieste d'incontro): un solo
/// socket fisico per sessione, ognuno filtra i messaggi del proprio
/// `"type"` dallo stesso stream. Tenerlo qui in `core/` invece che dentro
/// una delle due feature evita che una dipenda dall'altra solo per
/// condividere il canale.
class RealtimeConnection {
  RealtimeConnection._();

  static final RealtimeConnection instance = RealtimeConnection._();

  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _messages;
  String? _sessionId;

  /// Apre la connessione per `sessionId` se non già aperta per la stessa
  /// sessione (chiamabile da più feature, la prima vince); ritorna lo
  /// stream broadcast dei messaggi JSON in arrivo, condiviso da tutti gli
  /// ascoltatori.
  Stream<Map<String, dynamic>> connect(String sessionId) {
    if (_channel != null && _sessionId == sessionId) {
      return _messages!.stream;
    }

    _sessionId = sessionId;
    final uri = Uri.parse(
      '${ApiConfig.wsBaseUrl}/ws',
    ).replace(queryParameters: {'sessionId': sessionId});
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    // Vedi lo stesso gotcha in nearby_remote_data_source_impl.dart: l'errore
    // vero arriva comunque come evento sullo stream qui sotto.
    unawaited(channel.ready.catchError((_) {}));

    final messages = StreamController<Map<String, dynamic>>.broadcast();
    _messages = messages;

    channel.stream.listen(
      (raw) {
        final Object? decoded;
        try {
          decoded = jsonDecode(raw as String);
        } catch (_) {
          return;
        }
        if (decoded is Map<String, dynamic>) messages.add(decoded);
      },
      onError: messages.addError,
      onDone: messages.close,
    );

    return messages.stream;
  }

  /// Manda un messaggio sulla connessione già aperta — non fa nulla se non
  /// è aperta (fire-and-forget, coerente con "usa e getta": nessuna coda,
  /// nessun retry).
  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  /// Chiude la connessione — il server se ne accorge subito e pulisce sia
  /// la presenza sia le richieste d'incontro pendenti di questa sessione.
  /// **Best-effort con timeout**: se il socket è già in uno stato bloccato
  /// (es. rete caduta a metà, foreground service ucciso) `sink.close()` può
  /// non completarsi mai — senza un limite, chi chiama `disconnect()` (in
  /// particolare `ProSession.end()`, il bottone End) resterebbe bloccato
  /// per sempre prima di poter tornare offline in locale. Dopo il timeout
  /// si abbandona comunque il canale: il server lo scoprirà da sé quando
  /// la connessione decade (`purgeStale`), ma l'utente non deve aspettarlo.
  Future<void> disconnect() async {
    try {
      await Future.wait([
        if (_channel != null) _channel!.sink.close(),
        if (_messages != null) _messages!.close(),
      ]).timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ignorato di proposito: vedi il commento sopra.
    }
    _channel = null;
    _sessionId = null;
    _messages = null;
  }
}
