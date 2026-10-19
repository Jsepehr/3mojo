/// Limita quante volte la stessa chiave (tipicamente un IP) può fare
/// un'azione in una finestra di tempo scorrevole. Solo in RAM: per ogni
/// chiave si tengono gli orari delle ultime azioni, e solo per la durata
/// della finestra.
class SlidingWindowRateLimiter {
  SlidingWindowRateLimiter({
    required this.maxActions,
    required this.window,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxActions;
  final Duration window;
  final DateTime Function() _now;
  final Map<String, List<DateTime>> _actionsByKey = {};

  /// Registra un'azione per [key] e dice se è consentita.
  bool tryAcquire(String key) {
    final now = _now();
    _actionsByKey.removeWhere(
      (_, actions) => actions.every((t) => now.difference(t) >= window),
    );

    final actions = _actionsByKey.putIfAbsent(key, () => [])
      ..removeWhere((t) => now.difference(t) >= window);
    if (actions.length >= maxActions) return false;
    actions.add(now);
    return true;
  }
}

/// `POST /paywall/purchase` per IP: ogni chiamata crea un token in memoria,
/// senza limite chiunque potrebbe riempire la RAM del server. Lo stesso IP
/// può essere condiviso da molte persone (Wi-Fi di un locale, CGNAT), quindi
/// il tetto non è basso.
final purchaseRateLimiter = SlidingWindowRateLimiter(
  maxActions: 10,
  window: const Duration(minutes: 10),
);

/// Limite di messaggi **per singola connessione** WebSocket (token bucket):
/// [burst] messaggi di fila, poi [refillPerSecond] al secondo. Un client
/// normale manda una presenza ogni qualche secondo, un ping ogni 20 s e
/// qualche messaggio di chat: tutto ben sotto. Oltre, i messaggi vengono
/// scartati (vedi `SocketSession`).
class ConnectionRateLimiter {
  ConnectionRateLimiter({
    this.burst = 20,
    this.refillPerSecond = 5,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _tokens = burst.toDouble();

  final int burst;
  final double refillPerSecond;
  final DateTime Function() _now;
  double _tokens;
  DateTime? _lastRefill;

  /// Consuma un gettone: `false` se la connessione sta mandando troppo.
  bool tryConsume() {
    final now = _now();
    final last = _lastRefill;
    if (last != null) {
      final elapsedSeconds = now.difference(last).inMicroseconds / 1e6;
      _tokens = (_tokens + elapsedSeconds * refillPerSecond).clamp(
        0,
        burst.toDouble(),
      );
    }
    _lastRefill = now;
    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }
}
