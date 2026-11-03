import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

/// Tiene gli sblocchi a pagamento attivi — un singleton come
/// `SessionStore`/`EncounterStore`. **In RAM e basta, salvo una
/// eccezione voluta**: ciò che si è pagato non deve sparire a un riavvio
/// del server (deploy notturno, crash). Per questo gli sblocchi attivi sono
/// anche scritti su disco da `UnlockStatePersistence` — **solo** come
/// SHA-256 del token e ora dello sblocco, finché vale (2 ore), cifrati; mai
/// il token in chiaro né nulla della persona.
///
/// Anche in RAM le chiavi sono gli hash: il token in chiaro esiste solo nel
/// client e nel momento in cui il server lo emette o lo riceve.
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
  final Map<String, DateTime> _unlockedAtByTokenHash = {};

  /// `true` con `PAYWALL_MODE=free` (impostato all'avvio da `main.dart`):
  /// chiunque vede ogni foto, anche senza uno sblocco. Cambia **solo** la
  /// visibilità delle persone vicine: emissione, stato e scadenza degli
  /// sblocchi restano quelli di sempre.
  bool everyoneUnlocked = false;

  /// Chiamata a ogni cambiamento da salvare (emissione, revoca): la
  /// imposta `UnlockStatePersistence`.
  void Function()? onChanged;

  /// SHA-256 esadecimale di [token]: la chiave con cui lo sblocco vive in
  /// RAM e su disco.
  static String hashToken(String token) => SHA256Digest()
      .process(Uint8List.fromList(utf8.encode(token)))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  /// Registra un nuovo sblocco da ora (l'ora del server) e ritorna il token
  /// che lo rappresenta: 128 bit casuali, non derivati da nulla del client.
  String issueUnlockToken() {
    _dropExpired();
    final token = _newToken();
    _unlockedAtByTokenHash[hashToken(token)] = _now();
    onChanged?.call();
    return token;
  }

  /// Toglie subito lo sblocco rappresentato da [token] (es. acquisto
  /// rimborsato, `StoreNotifications`; o riscatto annullato perché il
  /// negozio non ha confermato, `UnlockPurchaseService`). `true` se valeva.
  bool revoke(String token) => revokeHash(hashToken(token));

  /// Come [revoke], da un hash (dopo un riavvio il registro delle
  /// transazioni conosce solo l'hash del token).
  bool revokeHash(String tokenHash) {
    final removed = _unlockedAtByTokenHash.remove(tokenHash) != null;
    if (removed) onChanged?.call();
    return removed;
  }

  /// Gli sblocchi ancora validi, per il salvataggio: hash del token →
  /// ora dello sblocco. Quelli scaduti non escono.
  Map<String, DateTime> exportUnlocks() {
    _dropExpired();
    return Map.of(_unlockedAtByTokenHash);
  }

  /// Rimette in vita gli sblocchi salvati (all'avvio), scartando quelli già
  /// scaduti. Non sostituisce quelli già presenti.
  void restoreUnlocks(Map<String, DateTime> unlocks) {
    for (final entry in unlocks.entries) {
      if (_isExpired(entry.value)) continue;
      _unlockedAtByTokenHash.putIfAbsent(entry.key, () => entry.value);
    }
  }

  int get activeCount {
    _dropExpired();
    return _unlockedAtByTokenHash.length;
  }

  /// Il token rappresenta uno sblocco ancora valido (entro le 2 ore)?
  bool isUnlocked(String token) => remainingFor(token) != null;

  /// Quanto resta dello sblocco rappresentato da [token], sull'orologio del
  /// server, o `null` se non vale (sconosciuto o scaduto). È ciò che il
  /// client usa per mostrare il tempo residuo: lo somma al **proprio** "ora"
  /// al momento della risposta, così un orologio del telefono sbagliato di
  /// qualche ora non sposta la scadenza (e non decide nulla: il paywall lo
  /// applica sempre e solo il server).
  Duration? remainingFor(String token) {
    final hash = hashToken(token);
    final unlockedAt = _unlockedAtByTokenHash[hash];
    if (unlockedAt == null) return null;
    if (_isExpired(unlockedAt)) {
      _unlockedAtByTokenHash.remove(hash);
      return null;
    }
    return unlockDuration - _now().difference(unlockedAt);
  }

  /// [remainingFor] in secondi interi per le risposte HTTP, arrotondato per
  /// **difetto** (meglio dire un secondo in meno che uno in più); `0` se non
  /// vale.
  int remainingSecondsFor(String token) => remainingFor(token)?.inSeconds ?? 0;

  bool _isExpired(DateTime unlockedAt) =>
      _now().difference(unlockedAt) >= unlockDuration;

  /// Un token scaduto non serve più a nulla: tenerlo sarebbe solo un dato
  /// in più senza scopo.
  void _dropExpired() => _unlockedAtByTokenHash.removeWhere(
    (_, unlockedAt) => _isExpired(unlockedAt),
  );

  String _newToken() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
