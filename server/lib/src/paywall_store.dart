import 'dart:math';

/// Tiene in RAM gli sblocchi a pagamento attivi — un singleton come
/// `SessionStore`/`EncounterStore`, stessa filosofia (nessuna persistenza:
/// riavvii il server e ogni sblocco sparisce, un vero prodotto avrebbe
/// bisogno di un database).
///
/// **Token, non dispositivi**: a ogni acquisto il server emette un token
/// casuale valido [unlockDuration]. Chi non paga non ha nessun token, quindi
/// non è identificato in alcun modo; chi paga lo è solo per quelle 2 ore,
/// poi il token non vale più nulla e non collega niente. Prima c'era un
/// `deviceId` fisso per installazione, mandato con ogni presenza: legava
/// tra loro tutte le sessioni dello stesso telefono, giorno dopo giorno,
/// insieme a posizione, selfie, genere e preferenza.
///
/// **Orologio del server** (`_now`), mai quello del client: un client può
/// cambiare l'ora del telefono, il server no.
class PaywallStore {
  PaywallStore._({DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure();

  /// Solo per i test: un'istanza con orologio controllabile, invece del
  /// singleton condiviso con `DateTime.now()` reale.
  factory PaywallStore.withClock(DateTime Function() now) =>
      PaywallStore._(now: now);

  static final PaywallStore instance = PaywallStore._();

  static const unlockDuration = Duration(hours: 2);

  final DateTime Function() _now;
  final Random _random;
  final Map<String, DateTime> _unlockedAtByToken = {};

  /// Registra un nuovo sblocco da ora (l'ora del server) e ritorna il token
  /// che lo rappresenta: 128 bit casuali, non derivati da nulla del client.
  String issueUnlockToken() {
    _dropExpired();
    final token = _newToken();
    _unlockedAtByToken[token] = _now();
    return token;
  }

  /// Il token rappresenta uno sblocco ancora valido (entro le 2 ore)?
  bool isUnlocked(String token) {
    final unlockedAt = _unlockedAtByToken[token];
    if (unlockedAt == null) return false;
    if (_isExpired(unlockedAt)) {
      _unlockedAtByToken.remove(token);
      return false;
    }
    return true;
  }

  bool _isExpired(DateTime unlockedAt) =>
      _now().difference(unlockedAt) >= unlockDuration;

  /// Un token scaduto non serve più a nulla: tenerlo sarebbe solo un dato
  /// in più senza scopo.
  void _dropExpired() =>
      _unlockedAtByToken.removeWhere((_, unlockedAt) => _isExpired(unlockedAt));

  String _newToken() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
