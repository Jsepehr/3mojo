import 'dart:async';
import 'dart:convert';

import 'package:threemojo_server/src/encounter_store.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/session_store.dart';

/// Tiene i canali WebSocket dei client online e spinge a ognuno gli
/// aggiornamenti che lo riguardano — "vicinanze" e richieste d'incontro —
/// sostituendo il polling HTTP con un push quasi istantaneo. Non tiene lo
/// stream in ingresso (quello lo legge direttamente la route `/ws`, che sa
/// interpretare i messaggi): solo il lato di scrittura, cosicché resti
/// testabile senza un vero `WebSocketChannel`.
class ConnectionHub {
  ConnectionHub._(this._sessionStore, this._encounterStore, this._paywallStore);

  /// Solo per i test: un hub agganciato a store controllabili invece dei
  /// singleton condivisi.
  factory ConnectionHub.withStore(
    SessionStore sessionStore, {
    EncounterStore? encounterStore,
    PaywallStore? paywallStore,
  }) => ConnectionHub._(
    sessionStore,
    encounterStore ?? EncounterStore.instance,
    paywallStore ?? PaywallStore.instance,
  );

  static final ConnectionHub instance = ConnectionHub._(
    SessionStore.instance,
    EncounterStore.instance,
    PaywallStore.instance,
  );

  static const double radiusMeters = 100;

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
  final Map<String, StreamSink<dynamic>> _sinks = {};
  Timer? _hotspotDetectionTimer;

  /// Avvia (se non già attivo) il rilevamento periodico degli hotspot —
  /// non è automatico dentro il costruttore, stesso motivo e stessa forma di
  /// `SessionStore.startAutoPurge` (`interval` iniettabile per i test, non
  /// far scattare timer veri nei test che usano `ConnectionHub.withStore`
  /// senza mai chiamare questo metodo).
  void startHotspotDetection({Duration interval = hotspotDetectionInterval}) {
    _hotspotDetectionTimer ??= Timer.periodic(interval, (_) {
      HotspotStore.instance.detectAndRefresh(_sessionStore.allSessions);
      broadcastNearbyUpdates();
    });
  }

  /// Solo per i test: ferma il timer avviato da [startHotspotDetection], per
  /// non lasciarlo pendente dopo che un test finisce (stesso gotcha già
  /// capitato con `ProNearby`/`ProEncounters` — vedi guida sviluppatori).
  void stopHotspotDetection() {
    _hotspotDetectionTimer?.cancel();
    _hotspotDetectionTimer = null;
  }

  void register(String sessionId, StreamSink<dynamic> sink) {
    _sinks[sessionId] = sink;
  }

  void unregister(String sessionId) {
    _sinks.remove(sessionId);
  }

  void _sendTo(String sessionId, Map<String, dynamic> message) {
    _sinks[sessionId]?.add(jsonEncode(message));
  }

  /// Inoltra un messaggio di chat a `toSessionId`, se connesso in questo
  /// momento — il server fa solo da postino, non lo conserva da nessuna
  /// parte: se il destinatario non è online, il messaggio va perso (chi
  /// l'ha mandato lo tiene comunque nella propria cronologia locale).
  void relayChatMessage({
    required String fromSessionId,
    required String toSessionId,
    required String text,
    required String sentAt,
  }) {
    _sendTo(toSessionId, {
      'type': 'chatMessage',
      'fromSessionId': fromSessionId,
      'text': text,
      'sentAt': sentAt,
    });
  }

  /// Ricalcola e manda a ognuno dei client connessi la sua lista
  /// "vicinanze" aggiornata (ognuno riceve la propria, già filtrata per
  /// genere/raggio/permanenza da `SessionStore.nearbyPeople`, ed
  /// eventualmente allargata da un hotspot attivo — vedi `HotspotStore`).
  /// Non rileva/rinnova hotspot di persona: usa quelli già noti in questo
  /// momento a `HotspotStore.instance` — vedi `startHotspotDetection`.
  void broadcastNearbyUpdates() {
    for (final sessionId in _sinks.keys) {
      final people = _sessionStore.nearbyPeople(
        sessionId: sessionId,
        radiusMeters: radiusMeters,
        hotspotStore: HotspotStore.instance,
        paywallStore: _paywallStore,
      );
      if (people == null) continue;

      _sendTo(sessionId, {
        'type': 'nearby',
        'people': people.map((p) => p.toJson()).toList(),
      });
    }
  }

  /// Manda a `sessionId` (se connesso) le sue richieste in entrata/uscita
  /// aggiornate, con selfie della controparte preso da `SessionStore` —
  /// niente da conservare nella richiesta stessa, sempre fresco.
  void pushEncounterSnapshot(String sessionId) {
    if (!_sinks.containsKey(sessionId)) return;

    Map<String, dynamic> toJson(EncounterRequest r) {
      final other = _sessionStore.selfieBase64For(r.otherSessionId(sessionId));
      return {
        'id': r.id,
        'otherSessionId': r.otherSessionId(sessionId),
        'otherSelfieBase64': other ?? '',
        'status': r.status.name,
      };
    }

    _sendTo(sessionId, {
      'type': 'encounters',
      'incoming': _encounterStore.incomingFor(sessionId).map(toJson).toList(),
      'outgoing': _encounterStore.outgoingFor(sessionId).map(toJson).toList(),
    });
  }
}
