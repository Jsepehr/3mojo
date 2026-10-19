import 'dart:async';

import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/encounter_store.dart';
import 'package:threemojo_server/src/new_session_rate_limiter.dart';
import 'package:threemojo_server/src/session_credentials.dart';
import 'package:threemojo_server/src/session_store.dart';

/// Esito di un `hello` (il primo messaggio di ogni socket, vedi
/// [SessionLifecycle.hello]).
sealed class HelloOutcome {
  const HelloOutcome();
}

/// Segreto accettato: [publicId] è l'id interno della sessione, [resumed]
/// dice se è la stessa sessione di prima (riconnessione entro la grazia o
/// con un socket ancora aperto) o una nuova.
class HelloAccepted extends HelloOutcome {
  const HelloAccepted({required this.publicId, required this.resumed});

  final String publicId;
  final bool resumed;
}

/// Segreto mancante o malformato.
class HelloInvalidSecret extends HelloOutcome {
  const HelloInvalidSecret();
}

/// Troppi nuovi Start dallo stesso IP (`NewSessionRateLimiter`).
class HelloRateLimited extends HelloOutcome {
  const HelloRateLimited();
}

/// Nasce, sopravvive a una caduta della rete e finisce una sessione — **un
/// solo punto** in cui una sessione finisce davvero ([endNow]), qualunque
/// sia il motivo:
/// - **End esplicito**: il client manda `{"type": "end"}` prima di chiudere
///   → [endNow] subito;
/// - **caduta** (socket chiuso senza `end`: rete persa, app uccisa, cambio
///   Wi-Fi/4G) → la sessione viene **nascosta** da "Vicinanze" e parte un
///   periodo di grazia ([gracePeriod]). Se lo stesso segreto si riconnette
///   entro la grazia riprende **la stessa** sessione: stesso id, stessa
///   permanenza (`arrivedAt`), stesse richieste e stesso match, e non conta
///   come nuovo Start per `NewSessionRateLimiter`. Altrimenti, allo
///   scadere, [endNow];
/// - **silenzio** (nessun messaggio da più di `maxAge`, vedi
///   [startAutoPurge]) → [endNow], che chiude anche il socket.
///
/// [endNow] toglie la sessione da `SessionStore`, dimentica la credenziale,
/// cancella le richieste pendenti, chiude il match attivo (`accepted` →
/// `ended`) avvisando subito i partner, e infine toglie da `EncounterStore`
/// ogni richiesta della sessione (prima crescevano per sempre).
class SessionLifecycle {
  SessionLifecycle({
    required SessionStore sessions,
    required EncounterStore encounters,
    required ConnectionHub hub,
    required SessionCredentials credentials,
    required NewSessionRateLimiter rateLimiter,
    this.gracePeriod = defaultGracePeriod,
    DateTime Function()? now,
  }) : _sessions = sessions,
       _encounters = encounters,
       _hub = hub,
       _credentials = credentials,
       _rateLimiter = rateLimiter,
       _now = now ?? DateTime.now;

  static final SessionLifecycle instance = SessionLifecycle(
    sessions: SessionStore.instance,
    encounters: EncounterStore.instance,
    hub: ConnectionHub.instance,
    credentials: SessionCredentials.instance,
    rateLimiter: NewSessionRateLimiter.instance,
  );

  /// Abbastanza per un cambio di rete o un tunnel, abbastanza poco perché
  /// chi è davvero andato via non resti "in sospeso" a lungo per il partner.
  /// Il client si riconnette con backoff 0,5→30 s: entro 45 s fa almeno 5-6
  /// tentativi.
  static const defaultGracePeriod = Duration(seconds: 45);

  /// Codice di chiusura WebSocket usato quando è il server a chiudere la
  /// sessione (purge per silenzio).
  static const closeCodeSessionEnded = 4010;

  final SessionStore _sessions;
  final EncounterStore _encounters;
  final ConnectionHub _hub;
  final SessionCredentials _credentials;
  final NewSessionRateLimiter _rateLimiter;
  final DateTime Function() _now;
  final Duration gracePeriod;

  final Map<String, Timer> _graceTimers = {};

  /// Ultimo messaggio ricevuto per ogni sessione autenticata — anche per
  /// chi non ha ancora mandato una presenza (e quindi non è in
  /// `SessionStore`), così anche un socket che saluta e poi tace finisce.
  final Map<String, DateTime> _lastSeen = {};
  Timer? _autoPurgeTimer;

  /// `true` se [sessionId] è nel periodo di grazia.
  bool isInGrace(String sessionId) => _graceTimers.containsKey(sessionId);

  /// Verifica il segreto del primo messaggio del socket. Un segreto ancora
  /// legato a una sessione viva (connessa o nel periodo di grazia) è una
  /// **riconnessione**: non conta per il limite ai nuovi Start.
  HelloOutcome hello({required String? secret, required String ip}) {
    if (!SessionCredentials.isValidSecret(secret)) {
      return const HelloInvalidSecret();
    }
    final resumed = _credentials.knows(secret!);
    if (!resumed && !_rateLimiter.tryStart(ip)) {
      return const HelloRateLimited();
    }
    return HelloAccepted(
      publicId: _credentials.publicIdFor(secret),
      resumed: resumed,
    );
  }

  /// Collega il socket appena autenticato: annulla un'eventuale grazia in
  /// corso, rende di nuovo visibile la sessione, manda `welcome`, lo stato
  /// delle richieste e una lista "vicinanze" fresca.
  void attach(
    String sessionId,
    StreamSink<dynamic> sink, {
    required bool resumed,
  }) {
    _graceTimers.remove(sessionId)?.cancel();
    _lastSeen[sessionId] = _now();
    _hub.register(sessionId, sink);
    _sessions
      ..setConnected(sessionId, connected: true)
      ..touch(sessionId);
    _hub
      ..sendTo(sessionId, {
        'type': 'welcome',
        'resumed': resumed,
        'graceSeconds': gracePeriod.inSeconds,
      })
      // Stato già esistente (es. richieste ricevute prima di una
      // riconnessione) — non aspettare il prossimo cambiamento per vederlo.
      ..pushEncounterSnapshot(sessionId)
      ..broadcastNearbyUpdates();
  }

  /// Un messaggio qualsiasi è arrivato da [sessionId].
  void touch(String sessionId) {
    if (_lastSeen.containsKey(sessionId)) _lastSeen[sessionId] = _now();
    _sessions.touch(sessionId);
  }

  /// Il socket [sink] di [sessionId] si è chiuso. Se nel frattempo la
  /// sessione si è già riconnessa con un altro socket (o è già finita),
  /// non fa nulla. Con [explicitEnd] (il client ha mandato `end`) la
  /// sessione finisce subito; altrimenti parte il periodo di grazia.
  void detach(
    String sessionId,
    StreamSink<dynamic> sink, {
    required bool explicitEnd,
  }) {
    final wasCurrent = _hub.unregister(sessionId, sink: sink);
    if (!wasCurrent) return;

    if (explicitEnd) {
      endNow(sessionId);
      return;
    }

    _sessions.setConnected(sessionId, connected: false);
    _hub.broadcastNearbyUpdates();
    _graceTimers.remove(sessionId)?.cancel();
    _graceTimers[sessionId] = Timer(gracePeriod, () {
      _graceTimers.remove(sessionId);
      if (_hub.isConnected(sessionId)) return;
      endNow(sessionId);
    });
  }

  /// **La** fine di una sessione — End, scadenza della grazia, purge. È
  /// idempotente: chiamarla due volte (es. `end` seguito dalla chiusura del
  /// socket) non fa danni.
  void endNow(String sessionId) {
    _graceTimers.remove(sessionId)?.cancel();
    _lastSeen.remove(sessionId);
    _hub.disconnect(sessionId);

    _sessions.remove(sessionId);
    _credentials.forgetPublicId(sessionId);

    final affected = [
      ..._encounters.cancelAllPendingFor(sessionId),
      ..._encounters.endActiveMatchesFor(sessionId),
    ];
    // Prima si avvisano le controparti (vedono la richiesta `cancelled` o il
    // match `ended`: la pagina del match si deve chiudere), poi si toglie
    // tutto ciò che riguarda la sessione.
    final partners = {
      for (final request in affected) request.otherSessionId(sessionId),
    };
    for (final partner in partners) {
      _hub.pushEncounterSnapshot(partner);
    }
    _encounters.forgetSession(sessionId);
    _hub
      ..forgetSession(sessionId)
      ..broadcastNearbyUpdates();
  }

  /// Termina (chiudendone il socket) ogni sessione silenziosa da più di
  /// [maxAge] — rete di sicurezza per i socket mezzi aperti che il ping del
  /// WebSocket non ha ancora chiuso, o per chi si collega e poi non manda
  /// più nulla. Il client manda un `ping` applicativo ogni 20 s, quindi una
  /// sessione viva non ci finisce mai. Ritorna gli id terminati.
  List<String> purgeStale(Duration maxAge) {
    final now = _now();
    final stale = [
      for (final entry in _lastSeen.entries)
        if (now.difference(entry.value) > maxAge) entry.key,
    ];
    for (final sessionId in stale) {
      _hub.disconnect(sessionId, code: closeCodeSessionEnded, reason: 'stale');
      endNow(sessionId);
    }
    return stale;
  }

  /// Avvia (se non già attivo) [purgeStale] periodico. Non è automatico nel
  /// costruttore per non far scattare timer nei test.
  void startAutoPurge({
    Duration interval = const Duration(seconds: 30),
    Duration maxAge = const Duration(seconds: 90),
  }) {
    _autoPurgeTimer ??= Timer.periodic(interval, (_) => purgeStale(maxAge));
  }

  /// Solo per i test: ferma ogni timer (purge e grazie in corso).
  void dispose() {
    _autoPurgeTimer?.cancel();
    _autoPurgeTimer = null;
    for (final timer in _graceTimers.values) {
      timer.cancel();
    }
    _graceTimers.clear();
  }
}
