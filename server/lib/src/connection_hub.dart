import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:threemojo_server/src/block_store.dart';
import 'package:threemojo_server/src/encounter_store.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/pseudonyms.dart';
import 'package:threemojo_server/src/session_store.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Tiene i canali WebSocket dei client online e spinge a ognuno gli
/// aggiornamenti che lo riguardano — "vicinanze", richieste d'incontro e
/// chat — sostituendo il polling HTTP con un push quasi istantaneo. Non
/// tiene lo stream in ingresso (quello lo legge `SocketSession`, che sa
/// interpretare i messaggi): solo il lato di scrittura, cosicché resti
/// testabile senza un vero `WebSocketChannel`.
///
/// **Pseudonimi**: è qui che gli id interni delle sessioni diventano, per
/// ogni destinatario, gli pseudonimi per osservatore di [Pseudonyms]. Nessun
/// id interno esce mai da questa classe verso un client.
class ConnectionHub {
  ConnectionHub._(
    this._sessionStore,
    this._encounterStore,
    this._paywallStore,
    this._hotspotStore,
    this.pseudonyms,
    this._blockStore, {
    Duration broadcastThrottleInterval =
        ConnectionHub.broadcastThrottleInterval,
    Duration nearbyPushMinInterval = ConnectionHub.nearbyPushMinInterval,
  }) : _broadcastThrottleInterval = broadcastThrottleInterval,
       _nearbyPushMinInterval = nearbyPushMinInterval;

  /// Solo per i test: un hub agganciato a store controllabili invece dei
  /// singleton condivisi.
  factory ConnectionHub.withStore(
    SessionStore sessionStore, {
    EncounterStore? encounterStore,
    PaywallStore? paywallStore,
    HotspotStore? hotspotStore,
    Pseudonyms? pseudonyms,
    BlockStore? blockStore,
    Duration broadcastThrottleInterval =
        ConnectionHub.broadcastThrottleInterval,
    Duration nearbyPushMinInterval = ConnectionHub.nearbyPushMinInterval,
  }) => ConnectionHub._(
    sessionStore,
    encounterStore ?? EncounterStore.instance,
    paywallStore ?? PaywallStore.instance,
    hotspotStore ?? HotspotStore.instance,
    pseudonyms ?? Pseudonyms(),
    blockStore ?? BlockStore.instance,
    broadcastThrottleInterval: broadcastThrottleInterval,
    nearbyPushMinInterval: nearbyPushMinInterval,
  );

  static final ConnectionHub instance = ConnectionHub._(
    SessionStore.instance,
    EncounterStore.instance,
    PaywallStore.instance,
    HotspotStore.instance,
    Pseudonyms(),
    BlockStore.instance,
  );

  static const double radiusMeters = 100;

  // `broadcastNearbyUpdates` ricalcola-e-spinge per OGNI sessione connessa,
  // e viene chiamato ad ogni singolo messaggio "presence" di CHIUNQUE sia
  // online -- con N persone online, il lavoro totale cresce peggio di N²
  // (N ricalcoli per messaggio, O(N) messaggi per intervallo). Nessun
  // ricalcolo va perso: la posizione è già scritta in `SessionStore`
  // all'istante (mai rallentata), solo il ricalcolo-e-invio, la parte
  // costosa, viene fatto al più una volta per questa finestra — vedi
  // `broadcastNearbyUpdates` sotto.
  static const Duration broadcastThrottleInterval = Duration(milliseconds: 500);

  /// Al più una lista "vicinanze" **diversa** ogni tanto **per
  /// osservatore** (il throttle sopra è globale: con traffico costante,
  /// da solo lascerebbe arrivare a ognuno un ricalcolo ogni 500 ms). Una
  /// lista cambiata entro questa finestra dall'ultimo invio a quella
  /// sessione parte alla fine della finestra, già ricalcolata con lo stato
  /// più recente — mai persa, solo rimandata. Difesa in profondità contro
  /// chi usa la lista come oracolo: le distanze vanno già da ancora ad
  /// ancora (vedi `SessionStore.nearbyPeople`), questo limita anche quanto
  /// spesso si può osservare un cambiamento qualsiasi. Il primo invio dopo
  /// un periodo di calma parte subito; resta attivo anche attraverso le
  /// riconnessioni (riaprire il socket non lo azzera).
  static const Duration nearbyPushMinInterval = Duration(seconds: 5);

  // Un hotspot si forma in minClusterSize/clusterMinDwellMinutes (minuti) e
  // vive un'ora: non serve rilevarlo di nuovo a ogni singolo aggiornamento
  // di presenza di chiunque sia online (che con molti utenti connessi
  // potrebbe voler dire decine di volte al secondo) — un ritardo di
  // rilevamento fino a questo intervallo è del tutto irrilevante su quelle
  // scale di tempo, e disaccoppiarlo dal ritmo dei messaggi mette un limite
  // superiore netto al carico, indipendente da quanti utenti/messaggi ci
  // sono. `broadcastNearbyUpdates` resta invece istantaneo a ogni presenza:
  // riflette sempre lo stato hotspot più recente, solo la sua *scoperta* è
  // rallentata.
  static const Duration hotspotDetectionInterval = Duration(seconds: 15);

  final SessionStore _sessionStore;
  final EncounterStore _encounterStore;
  final PaywallStore _paywallStore;
  final HotspotStore _hotspotStore;

  /// I blocchi tra sessioni: tolgono le persone dalle liste e fermano la
  /// chat (vedi `BlockStore`).
  final BlockStore _blockStore;

  /// Gli pseudonimi per osservatore — condivisi con
  /// `RealtimeMessageHandler`, che li ritraduce negli id interni.
  final Pseudonyms pseudonyms;

  final Duration _broadcastThrottleInterval;
  final Duration _nearbyPushMinInterval;
  final Map<String, StreamSink<dynamic>> _sinks = {};

  /// Per osservatore: la finestra di [nearbyPushMinInterval] aperta
  /// dall'ultimo invio di una lista "vicinanze", e chi ha avuto altro da
  /// ricevere nel frattempo (vedi [_pushNearbyTo]).
  final Map<String, Timer> _nearbyPushCooldowns = {};
  final Set<String> _nearbyPushPending = {};

  /// Firma dell'ultima lista "vicinanze" mandata a ogni sessione: se non è
  /// cambiato nulla (niente distanze nel payload, quindi capita spesso) non
  /// si rimanda — ogni lista porta i selfie, decine di KB a persona.
  final Map<String, int> _lastNearbySignature = {};

  /// Per ogni sessione, le richieste d'incontro di cui il selfie della
  /// controparte è **già partito sul socket attuale**: gli snapshot
  /// successivi non lo ripetono (decine di KB a richiesta, a ogni
  /// cambiamento). Si azzera a ogni nuovo socket ([register]) e alla fine
  /// della sessione: il client riparte da zero e li riceve di nuovo. Il
  /// client tiene il selfie già ricevuto per l'id della richiesta.
  final Map<String, Set<String>> _encounterSelfiesSent = {};
  Timer? _hotspotDetectionTimer;
  Timer? _broadcastThrottleTimer;
  bool _broadcastRequestedDuringThrottle = false;

  /// Avvia (se non già attivo) il rilevamento periodico degli hotspot —
  /// non è automatico dentro il costruttore, stesso motivo e stessa forma di
  /// `SessionLifecycle.startAutoPurge` (`interval` iniettabile per i test,
  /// non far scattare timer veri nei test che usano `ConnectionHub.withStore`
  /// senza mai chiamare questo metodo). Un errore nel rilevamento non deve
  /// mai uscire dal timer: in Dart un'eccezione non gestita in un timer
  /// può far cadere l'intero processo.
  void startHotspotDetection({Duration interval = hotspotDetectionInterval}) {
    _hotspotDetectionTimer ??= Timer.periodic(interval, (_) {
      try {
        _hotspotStore.detectAndRefresh(_sessionStore.allSessions);
      } catch (error, stackTrace) {
        developer.log(
          'Rilevamento hotspot fallito',
          error: error,
          stackTrace: stackTrace,
        );
      }
      broadcastNearbyUpdates();
    });
  }

  /// Solo per i test: ferma il timer avviato da [startHotspotDetection], per
  /// non lasciarlo pendente dopo che un test finisce (stesso gotcha già
  /// capitato con `ProNearby`/`ProEncounters` — vedi guida sviluppatori).
  void stopHotspotDetection() {
    _hotspotDetectionTimer?.cancel();
    _hotspotDetectionTimer = null;
    _broadcastThrottleTimer?.cancel();
    _broadcastThrottleTimer = null;
    for (final timer in _nearbyPushCooldowns.values) {
      timer.cancel();
    }
    _nearbyPushCooldowns.clear();
    _nearbyPushPending.clear();
  }

  /// Registra il canale di [sessionId]. Se ce n'era già uno (riconnessione
  /// prima che il server si accorgesse della caduta del vecchio), il vecchio
  /// viene chiuso: un solo socket vivo per sessione.
  void register(String sessionId, StreamSink<dynamic> sink) {
    final previous = _sinks[sessionId];
    _sinks[sessionId] = sink;
    _lastNearbySignature.remove(sessionId);
    _encounterSelfiesSent.remove(sessionId);
    if (previous != null && !identical(previous, sink)) {
      _closeSink(previous, 4011, 'replaced');
    }
  }

  /// Stacca il canale di [sessionId]. Con [sink], solo se è ancora quello
  /// registrato: quando una sessione si riconnette, la chiusura in ritardo
  /// del vecchio socket non deve staccare quello nuovo. Ritorna `true` se ha
  /// davvero staccato qualcosa.
  bool unregister(String sessionId, {StreamSink<dynamic>? sink}) {
    final current = _sinks[sessionId];
    if (current == null) return false;
    if (sink != null && !identical(current, sink)) return false;
    _sinks.remove(sessionId);
    _lastNearbySignature.remove(sessionId);
    _encounterSelfiesSent.remove(sessionId);
    return true;
  }

  /// `true` se [sessionId] ha un socket registrato in questo momento.
  bool isConnected(String sessionId) => _sinks.containsKey(sessionId);

  /// Stacca **e chiude** il socket di [sessionId] (se c'è), con un codice
  /// di chiusura WebSocket: usato a fine sessione (End, purge) — il client
  /// deve accorgersene subito, non restare appeso a un canale morto.
  void disconnect(String sessionId, {int code = 1000, String reason = ''}) {
    final sink = _sinks.remove(sessionId);
    _lastNearbySignature.remove(sessionId);
    _encounterSelfiesSent.remove(sessionId);
    _forgetNearbyPushCooldown(sessionId);
    if (sink != null) _closeSink(sink, code, reason);
  }

  /// Dimentica tutto ciò che riguarda [sessionId] (pseudonimi in cui
  /// compare, firme, appartenenza agli hotspot) — alla fine della sessione.
  void forgetSession(String sessionId) {
    pseudonyms.forget(sessionId);
    _hotspotStore.forgetSession(sessionId);
    _lastNearbySignature.remove(sessionId);
    _encounterSelfiesSent.remove(sessionId);
    _forgetNearbyPushCooldown(sessionId);
  }

  void _forgetNearbyPushCooldown(String sessionId) {
    _nearbyPushCooldowns.remove(sessionId)?.cancel();
    _nearbyPushPending.remove(sessionId);
  }

  void _closeSink(StreamSink<dynamic> sink, int code, String reason) {
    try {
      if (sink is WebSocketSink) {
        unawaited(sink.close(code, reason).catchError((Object _) {}));
      } else {
        unawaited(sink.close().catchError((Object _) {}));
      }
    } catch (_) {
      // Già chiuso: niente da fare.
    }
  }

  /// Manda [message] a [sessionId], se connesso. Un sink già chiuso non
  /// deve far fallire chi chiama (es. il broadcast per tutti gli altri).
  void sendTo(String sessionId, Map<String, dynamic> message) {
    final sink = _sinks[sessionId];
    if (sink == null) return;
    try {
      sink.add(jsonEncode(message));
    } catch (error) {
      developer.log('Invio a una sessione fallito', error: error);
    }
  }

  /// Inoltra un messaggio di chat a `toSessionId` (id interno), se connesso
  /// in questo momento — il server fa solo da postino, non lo conserva da
  /// nessuna parte: se il destinatario non è online, il messaggio va perso.
  /// L'ora (`sentAt`) è quella del server, non una dichiarata dal client.
  ///
  /// Solo tra due sessioni con un match attivo: senza, chiunque abbia visto
  /// un id nella lista vicinanze potrebbe scrivere a quella persona senza
  /// che abbia mai accettato nulla. Ritorna `true` solo se il messaggio è
  /// davvero partito verso il destinatario.
  bool relayChatMessage({
    required String fromSessionId,
    required String toSessionId,
    required String text,
  }) {
    if (!_encounterStore.hasActiveMatch(fromSessionId, toSessionId)) {
      return false;
    }
    // Difesa in profondità: un blocco chiude già il match, ma la chat tra
    // due sessioni bloccate non deve passare in nessun caso.
    if (_blockStore.isBlockedEitherWay(fromSessionId, toSessionId)) {
      return false;
    }
    if (!_sinks.containsKey(toSessionId)) return false;
    sendTo(toSessionId, {
      'type': 'chatMessage',
      'fromPersonId': pseudonyms.idFor(
        viewerId: toSessionId,
        targetId: fromSessionId,
      ),
      'text': text,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
    });
    return true;
  }

  /// Ricalcola e manda a ognuno dei client connessi la sua lista
  /// "vicinanze" aggiornata (ognuno riceve la propria, già filtrata per
  /// genere/raggio/permanenza da `SessionStore.nearbyPeople`, ed
  /// eventualmente allargata da un hotspot attivo — vedi `HotspotStore`).
  /// Non rileva/rinnova hotspot di persona: usa quelli già noti in questo
  /// momento — vedi `startHotspotDetection`.
  ///
  /// **Throttle** (leading+trailing, vedi [broadcastThrottleInterval]): la
  /// prima chiamata dopo un periodo di calma parte subito (nessun ritardo
  /// percepibile con poco traffico) — le chiamate successive entro la
  /// finestra non ricalcolano di nuovo, si limitano a segnare "è arrivato
  /// altro" (`_broadcastRequestedDuringThrottle`); alla fine della finestra,
  /// se è successo, parte **un solo** ricalcolo in più che vede comunque
  /// tutte le posizioni più recenti (già scritte in `SessionStore`
  /// all'istante da chi chiama — solo il ricalcolo-e-invio è rimandato, mai
  /// la scrittura). Così un ricalcolo completo costa al più una volta per
  /// finestra, invece che una volta per messaggio.
  void broadcastNearbyUpdates() {
    if (_broadcastThrottleTimer != null) {
      _broadcastRequestedDuringThrottle = true;
      return;
    }

    _pushNearbyToEveryone();
    _broadcastThrottleTimer = Timer(_broadcastThrottleInterval, () {
      _broadcastThrottleTimer = null;
      if (_broadcastRequestedDuringThrottle) {
        _broadcastRequestedDuringThrottle = false;
        broadcastNearbyUpdates();
      }
    });
  }

  void _pushNearbyToEveryone() {
    for (final sessionId in _sinks.keys.toList()) {
      // Un errore nel calcolo per una sessione (dato anomalo, bug) non deve
      // impedire a tutte le altre di ricevere la propria lista.
      try {
        _pushNearbyTo(sessionId);
      } catch (error, stackTrace) {
        developer.log(
          'Calcolo vicinanze fallito per una sessione',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// Manda a [sessionId] la sua lista, se è cambiata — ma al più una volta
  /// per [nearbyPushMinInterval]: dentro la finestra segna solo che c'è
  /// altro, e alla sua fine ricalcola e (se diversa) manda la lista più
  /// recente.
  void _pushNearbyTo(String sessionId) {
    if (_nearbyPushCooldowns.containsKey(sessionId)) {
      _nearbyPushPending.add(sessionId);
      return;
    }
    if (!_sendNearbyIfChanged(sessionId)) return;
    if (_nearbyPushMinInterval <= Duration.zero) return;

    _nearbyPushCooldowns[sessionId] = Timer(_nearbyPushMinInterval, () {
      _nearbyPushCooldowns.remove(sessionId);
      if (!_nearbyPushPending.remove(sessionId)) return;
      // Socket caduto nel frattempo: alla riconnessione `attach` chiede
      // comunque un ricalcolo.
      if (!_sinks.containsKey(sessionId)) return;
      try {
        _pushNearbyTo(sessionId);
      } catch (error, stackTrace) {
        developer.log(
          'Calcolo vicinanze fallito per una sessione',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
  }

  /// Ricalcola la lista di [sessionId] e la manda se è diversa dall'ultima
  /// mandata. Ritorna `true` solo se è partita davvero.
  bool _sendNearbyIfChanged(String sessionId) {
    final people = _sessionStore.nearbyPeople(
      sessionId: sessionId,
      radiusMeters: radiusMeters,
      hotspotStore: _hotspotStore,
      paywallStore: _paywallStore,
      blockStore: _blockStore,
    );
    if (people == null) return false;

    final payload = [
      for (final person in people)
        person.toJson(
          personId: pseudonyms.idFor(
            viewerId: sessionId,
            targetId: person.sessionId,
          ),
        ),
    ];
    final signature = Object.hashAll(
      payload.map(
        (p) => Object.hash(
          p['personId'],
          p['meetingChance'],
          p['locked'],
          p['selfieBase64'],
          p['intent'],
          Object.hashAll(p['languages'] as List? ?? const []),
          p['gender'],
        ),
      ),
    );
    if (_lastNearbySignature[sessionId] == signature) return false;
    _lastNearbySignature[sessionId] = signature;

    sendTo(sessionId, {'type': 'nearby', 'people': payload});
    return true;
  }

  /// Manda a `sessionId` (se connesso) le sue richieste in entrata/uscita
  /// aggiornate, con selfie e profilo visibile della controparte presi da
  /// `SessionStore` — niente da conservare nella richiesta stessa, sempre
  /// fresco. Del profilo solo ciò che la persona mostra anche in
  /// "Vicinanze" (intento, lingue, genere se scelto): mai chi cerca. Per le
  /// richieste finite (rifiutate, annullate, terminate) niente selfie né
  /// profilo: non servono più, e non devono continuare a circolare.
  ///
  /// **Banda**: il selfie di una richiesta parte una volta sola per socket
  /// (vedi [_encounterSelfiesSent]); gli snapshot successivi portano solo
  /// id, stato e profilo visibile, e il client riusa il selfie già
  /// ricevuto per quell'id.
  void pushEncounterSnapshot(String sessionId) {
    if (!_sinks.containsKey(sessionId)) return;
    final selfiesSent = _encounterSelfiesSent.putIfAbsent(
      sessionId,
      () => <String>{},
    );

    Map<String, dynamic> toJson(EncounterRequest r) {
      final otherId = r.otherSessionId(sessionId);
      final json = <String, dynamic>{
        'id': r.id,
        'otherPersonId': pseudonyms.idFor(
          viewerId: sessionId,
          targetId: otherId,
        ),
        'status': r.status.name,
        // Cosa ha proposto chi ha chiesto: lo vedono entrambi i lati, anche
        // a richiesta finita (è una scelta dell'app, non un dato del
        // profilo).
        'proposal': r.proposal,
      };
      if (terminalEncounterStatuses.contains(r.status)) {
        selfiesSent.remove(r.id);
        return json;
      }

      final selfie = selfiesSent.contains(r.id)
          ? ''
          : _sessionStore.selfieBase64For(otherId) ?? '';
      if (selfie.isNotEmpty) selfiesSent.add(r.id);
      final profile = _sessionStore.profileFor(otherId);
      final intent = profile?.intent;
      final languages = profile?.languages ?? const <String>[];
      final gender = profile?.visibleGender;
      return json..addAll({
        if (selfie.isNotEmpty) 'otherSelfieBase64': selfie,
        if (intent != null) 'otherIntent': intent,
        if (languages.isNotEmpty) 'otherLanguages': languages,
        if (gender != null) 'otherGender': gender,
      });
    }

    sendTo(sessionId, {
      'type': 'encounters',
      'incoming': _encounterStore.incomingFor(sessionId).map(toJson).toList(),
      'outgoing': _encounterStore.outgoingFor(sessionId).map(toJson).toList(),
    });
  }
}
