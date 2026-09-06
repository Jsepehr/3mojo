/// Tiene in RAM quando ogni dispositivo ha sbloccato l'accesso a pagamento
/// — un singleton come `SessionStore`/`EncounterStore`, stessa filosofia
/// (nessuna persistenza: riavvii il server e ogni sblocco sparisce, un
/// vero prodotto avrebbe bisogno di un database).
///
/// **Il punto centrale**: usa l'orologio del server (`_now`), mai quello
/// del client — un client può cambiare l'ora del telefono per far durare
/// uno sblocco pagato all'infinito, il server no. `deviceId` è un
/// identificatore anonimo generato una volta dal client e persistito in
/// locale (mai un nome, un'email, o un profilo) — serve solo a farsi
/// riconoscere tra un controllo e l'altro, come `sessionId` per le altre
/// feature, ma non usa-e-getta: deve sopravvivere a Start/End e alla
/// chiusura dell'app, altrimenti ogni riapertura perderebbe lo sblocco.
class PaywallStore {
  PaywallStore._({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Solo per i test: un'istanza con orologio controllabile, invece del
  /// singleton condiviso con `DateTime.now()` reale.
  factory PaywallStore.withClock(DateTime Function() now) =>
      PaywallStore._(now: now);

  static final PaywallStore instance = PaywallStore._();

  static const unlockDuration = Duration(hours: 2);

  final DateTime Function() _now;
  final Map<String, DateTime> _unlockedAt = {};

  /// Registra un nuovo sblocco da ora (l'ora del server) per `deviceId`.
  void recordUnlock(String deviceId) {
    _unlockedAt[deviceId] = _now();
  }

  /// Lo sblocco di `deviceId` è ancora valido (entro le 2 ore)?
  bool isUnlocked(String deviceId) {
    final unlockedAt = _unlockedAt[deviceId];
    if (unlockedAt == null) return false;
    return _now().difference(unlockedAt) < unlockDuration;
  }
}
