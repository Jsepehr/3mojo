import 'dart:math';

/// Attese tra un tentativo di riconnessione e il successivo: **esponenziali
/// con jitter**, da [initial] (0,5 s) fino a [max] (30 s).
///
/// Esponenziale: un server giù non viene martellato. Jitter: dopo un riavvio
/// del server (o un deploy), migliaia di client non si riconnettono tutti
/// nello stesso istante — ognuno aspetta tra metà e il tutto dell'attesa
/// nominale. I primi tentativi restano rapidi: entro i 45 s di grazia del
/// server se ne fanno almeno 5-6.
class ReconnectBackoff {
  ReconnectBackoff({
    this.initial = const Duration(milliseconds: 500),
    this.max = const Duration(seconds: 30),
    Random? random,
  }) : _random = random ?? Random();

  final Duration initial;
  final Duration max;
  final Random _random;
  int _attempt = 0;

  /// Quanti tentativi falliti di fila finora.
  int get attempt => _attempt;

  /// L'attesa prima del prossimo tentativo (e conta un tentativo in più).
  Duration next() {
    final nominalMs = min(
      max.inMilliseconds,
      initial.inMilliseconds * pow(2, _attempt).toInt(),
    );
    _attempt = min(_attempt + 1, 30);
    final jitteredMs = nominalMs / 2 + _random.nextDouble() * nominalMs / 2;
    return Duration(milliseconds: jitteredMs.round());
  }

  /// Salta subito all'attesa massima (es. il server ha detto "troppi
  /// tentativi").
  void jumpToMax() => _attempt = 30;

  /// Connessione riuscita: si riparte da [initial].
  void reset() => _attempt = 0;
}
