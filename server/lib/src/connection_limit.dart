import 'dart:io';

/// Tetto globale alle connessioni WebSocket **aperte** insieme
/// (`MAX_WS_CONNECTIONS`, default [defaultMax]). Ogni socket pesa in RAM (il
/// buffer, la sessione, un selfie fino a ~230 KB): senza un tetto,
/// riempire di connessioni il server è il modo più economico di mandarlo
/// fuori memoria. Oltre il tetto `GET /ws` risponde 503 con `Retry-After`,
/// prima ancora dell'upgrade; il client riprova con il suo backoff.
///
/// 2000 sessioni con il loro selfie sono ~0,5-1 GB: tarare insieme al
/// limite di memoria del container (`deploy/docker-compose.yml`). Il tetto
/// per IP e i tempi dei socket li mette il proxy (vedi `deploy/Caddyfile` e
/// `server/README.md`).
class WebSocketConnectionLimit {
  WebSocketConnectionLimit({this.max = defaultMax});

  factory WebSocketConnectionLimit.fromEnvironment(
    Map<String, String> environment,
  ) {
    final raw = int.tryParse((environment[environmentVariable] ?? '').trim());
    return WebSocketConnectionLimit(
      max: raw != null && raw > 0 ? raw : defaultMax,
    );
  }

  static final WebSocketConnectionLimit instance =
      WebSocketConnectionLimit.fromEnvironment(Platform.environment);

  static const environmentVariable = 'MAX_WS_CONNECTIONS';
  static const defaultMax = 2000;

  final int max;
  int _active = 0;

  int get active => _active;

  /// Prenota un posto: `false` se il tetto è raggiunto.
  bool tryAcquire() {
    if (_active >= max) return false;
    _active++;
    return true;
  }

  void release() {
    if (_active > 0) _active--;
  }

  /// `true` se in questo momento c'è ancora posto (per rifiutare **prima**
  /// dell'upgrade).
  bool get hasRoom => _active < max;
}
