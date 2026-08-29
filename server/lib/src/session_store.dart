import 'dart:async';

import 'package:threemojo_server/src/geo.dart';
import 'package:threemojo_server/src/meeting_chance.dart';

/// Una persona online: la sua posizione più recente, e da quando è "ferma"
/// nello stesso punto — l'ancora di stazionarietà, non la posizione grezza.
/// Se si sposta di più di [SessionStore.stationarityRadiusMeters] rispetto
/// all'**ancora** (non alla singola lettura precedente: vedi
/// `consecutiveAwayReadings`) per due letture di fila, l'ancora si aggiorna
/// e il tempo riparte da zero.
class Session {
  Session({
    required this.sessionId,
    required this.lat,
    required this.lng,
    required this.arrivedAt,
    required this.lastSeen,
    this.gender = 'unspecified',
    this.genderPreference = 'everyone',
    this.selfieBase64 = '',
  }) : anchorLat = lat,
       anchorLng = lng;

  final String sessionId;

  /// Ultima posizione nota — usata per le distanze verso le altre sessioni,
  /// aggiornata a ogni lettura senza filtri (qui la freschezza conta più
  /// della stabilità).
  double lat;
  double lng;

  /// Posizione di riferimento per il calcolo di stazionarietà/dwell —
  /// diversa da [lat]/[lng]: si sposta solo quando un allontanamento è
  /// confermato da letture consecutive, non a ogni singola lettura rumorosa.
  double anchorLat;
  double anchorLng;

  /// Quante letture di fila sono risultate oltre
  /// [SessionStore.stationarityRadiusMeters] dall'ancora attuale, senza
  /// ancora essere confermate come un vero spostamento.
  int consecutiveAwayReadings = 0;

  DateTime arrivedAt;
  DateTime lastSeen;

  /// Il genere dichiarato e la preferenza di chi vedere — stessi valori di
  /// `Gender`/`GenderPreference` nel client Flutter, qui solo stringhe
  /// perché il server non ha bisogno di interpretarli, solo di confrontarli.
  String gender;
  String genderPreference;

  /// Il selfie della sessione, così com'è arrivato dal client (base64) — il
  /// server non lo decodifica né lo valida, lo tiene solo per ridistribuirlo
  /// a chi lo vede in "Vicinanze".
  String selfieBase64;
}

/// Una persona vicina già pronta per il client: distanza, stadio di
/// probabilità d'incontro e selfie già pronti, nessuna posizione grezza
/// esposta.
class NearbyPersonResult {
  NearbyPersonResult({
    required this.sessionId,
    required this.distanceMeters,
    required this.meetingChance,
    required this.selfieBase64,
  });

  final String sessionId;
  final double distanceMeters;
  final MeetingChance meetingChance;
  final String selfieBase64;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'distanceMeters': distanceMeters,
    'meetingChance': meetingChance.name,
    'selfieBase64': selfieBase64,
  };
}

/// Tiene in memoria chi è online e la sua posizione. Un vero backend
/// userebbe un database persistente e più istanze del server — qui basta
/// un singleton in RAM per provare la logica con più client reali.
class SessionStore {
  SessionStore._({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Solo per i test: un'istanza con orologio controllabile, invece del
  /// singleton condiviso con `DateTime.now()` reale.
  factory SessionStore.withClock(DateTime Function() now) =>
      SessionStore._(now: now);

  static final SessionStore instance = SessionStore._();

  // Alzata da 30 a 60: il GPS di uno smartphone normale ha già di suo un
  // errore tipico di 5-20m (anche 30-50m a spot, indoor/urban canyon) — con
  // 30m bastava una singola lettura rumorosa per resettare la stazionarietà
  // di qualcuno fermo, facendolo sparire per un altro minuto senza essersi
  // mai davvero mosso (visto in test reali: due persone a ~40-80m stabili,
  // dwell resettato di continuo).
  static const double stationarityRadiusMeters = 60;

  /// Quante letture consecutive oltre [stationarityRadiusMeters] servono
  /// prima di considerare confermato un vero spostamento (invece di un
  /// singolo balzo rumoroso che poi torna vicino all'ancora).
  static const int confirmMovementReadings = 2;

  final DateTime Function() _now;
  final Map<String, Session> _sessions = {};
  Timer? _autoPurgeTimer;

  /// Aggiorna la posizione di `sessionId`. Se una lettura risulta oltre
  /// [stationarityRadiusMeters] dall'ancora attuale, non resetta subito la
  /// stazionarietà: serve che questo capiti per [confirmMovementReadings]
  /// letture di fila prima di considerarlo un vero spostamento ("è arrivata
  /// altrove", si riparte da zero) — un singolo balzo GPS isolato che poi
  /// torna vicino non conta.
  void upsertPosition({
    required String sessionId,
    required double lat,
    required double lng,
    String gender = 'unspecified',
    String genderPreference = 'everyone',
    String selfieBase64 = '',
  }) {
    final now = _now();
    final existing = _sessions[sessionId];

    if (existing == null) {
      _sessions[sessionId] = Session(
        sessionId: sessionId,
        lat: lat,
        lng: lng,
        arrivedAt: now,
        lastSeen: now,
        gender: gender,
        genderPreference: genderPreference,
        selfieBase64: selfieBase64,
      );
      return;
    }

    final looksAway =
        distanceMeters(existing.anchorLat, existing.anchorLng, lat, lng) >
        stationarityRadiusMeters;
    existing.consecutiveAwayReadings = looksAway
        ? existing.consecutiveAwayReadings + 1
        : 0;

    if (existing.consecutiveAwayReadings >= confirmMovementReadings) {
      existing.anchorLat = lat;
      existing.anchorLng = lng;
      existing.arrivedAt = now;
      existing.consecutiveAwayReadings = 0;
    }

    existing.lat = lat;
    existing.lng = lng;
    existing.lastSeen = now;
    existing.gender = gender;
    existing.genderPreference = genderPreference;
    existing.selfieBase64 = selfieBase64;
  }

  /// Rimuove `sessionId` dallo store — equivalente del bottone End (o della
  /// chiusura del WebSocket): chi esce non deve più comparire nella lista
  /// di nessuno.
  void remove(String sessionId) => _sessions.remove(sessionId);

  /// Il selfie di `sessionId`, così com'è arrivato dal client — usato da
  /// `ConnectionHub` per arricchire le richieste d'incontro con una foto
  /// sempre fresca, senza doverla conservare nella richiesta stessa.
  /// `null` se la sessione non è (più) online.
  String? selfieBase64For(String sessionId) => _sessions[sessionId]?.selfieBase64;

  /// Rete di sicurezza per quando un client sparisce senza chiudere il
  /// WebSocket in modo pulito (crash, rete che cade): rimuove le sessioni
  /// che non mandano un aggiornamento di presenza da più di [maxAge].
  /// Ritorna gli id rimossi, così chi tiene i canali collegati (vedi
  /// `ConnectionHub`) può anche chiuderli/notificare gli altri.
  List<String> purgeStale(Duration maxAge) {
    final now = _now();
    final staleIds = [
      for (final session in _sessions.values)
        if (now.difference(session.lastSeen) > maxAge) session.sessionId,
    ];
    staleIds.forEach(_sessions.remove);
    return staleIds;
  }

  /// Avvia (se non già attivo) la pulizia periodica di [purgeStale]. Non è
  /// automatico dentro il costruttore per non far scattare timer nei test
  /// che usano `SessionStore.withClock`.
  void startAutoPurge({
    Duration interval = const Duration(seconds: 30),
    Duration maxAge = const Duration(seconds: 90),
    void Function(List<String> removedIds)? onPurged,
  }) {
    _autoPurgeTimer ??= Timer.periodic(interval, (_) {
      final removed = purgeStale(maxAge);
      if (removed.isNotEmpty) onPurged?.call(removed);
    });
  }

  /// Persone entro [radiusMeters] da `sessionId`, con probabilità d'incontro
  /// già calcolata. Ritorna `null` se `sessionId` non ha ancora mandato una
  /// posizione (deve prima chiamare `POST /presence`).
  List<NearbyPersonResult>? nearbyPeople({
    required String sessionId,
    required double radiusMeters,
  }) {
    final me = _sessions[sessionId];
    if (me == null) return null;

    final now = _now();
    final results = <NearbyPersonResult>[];

    for (final other in _sessions.values) {
      if (other.sessionId == sessionId) continue;

      // "Il genere che l'utente vuole vedere in Vicinanze" — filtro a senso
      // unico sulla mia preferenza, non serve reciprocità.
      if (me.genderPreference != 'everyone' &&
          other.gender != me.genderPreference) {
        continue;
      }

      final distance = distanceMeters(me.lat, me.lng, other.lat, other.lng);
      if (distance > radiusMeters) continue;

      final dwell = now.difference(other.arrivedAt);
      if (dwell.inMinutes < visibilityThresholdMinutes) continue;

      results.add(
        NearbyPersonResult(
          sessionId: other.sessionId,
          distanceMeters: distance,
          meetingChance: meetingChanceFor(dwell),
          selfieBase64: other.selfieBase64,
        ),
      );
    }

    return results;
  }

  /// Solo per debug locale: tutte le sessioni in memoria, senza filtri di
  /// raggio/genere/tempo di permanenza — per verificare "chi risulta al
  /// server" indipendentemente da cosa vede un client specifico. Niente
  /// posizione grezza né selfie: solo ciò che serve a controllare che una
  /// sessione sia arrivata. `distanceMetersToOthers` (anch'essa derivata,
  /// non la posizione grezza) aiuta a distinguere "troppo lontani" da
  /// "genere/permanenza" quando qualcuno non si vede.
  List<Map<String, dynamic>> debugSnapshot() {
    final now = _now();
    final sessions = _sessions.values.toList();
    return sessions
        .map(
          (s) => {
            'sessionId': s.sessionId,
            'gender': s.gender,
            'genderPreference': s.genderPreference,
            'dwellSeconds': now.difference(s.arrivedAt).inSeconds,
            'lastSeenSecondsAgo': now.difference(s.lastSeen).inSeconds,
            'distanceMetersToOthers': {
              for (final other in sessions)
                if (other.sessionId != s.sessionId)
                  other.sessionId: distanceMeters(
                    s.lat,
                    s.lng,
                    other.lat,
                    other.lng,
                  ),
            },
          },
        )
        .toList();
  }
}
