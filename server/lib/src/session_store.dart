import 'dart:async';
import 'dart:math' as math;

import 'package:threemojo_server/src/geo.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/meeting_chance.dart';
import 'package:threemojo_server/src/paywall_store.dart';

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
    this.deviceId = '',
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

  /// L'identificatore anonimo persistente del dispositivo (`core/device/` nel
  /// client, mai il `sessionId` — quello è usa-e-getta), mandato con la
  /// presenza solo per poter chiedere a `PaywallStore` se questo dispositivo
  /// ha sbloccato l'accesso completo. Stringa vuota finché il client non
  /// l'ha ancora collegato (subito dopo il connect, vedi
  /// `NearbyRemoteDataSourceImpl._attachDeviceId` lato client) — trattata
  /// come "non sbloccato", mai come errore.
  String deviceId;
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

  // Indice spaziale: bucket per fascia di latitudine larga
  // `_gridBandMeters`, mantenuto incrementale ad ogni upsertPosition/
  // remove/purgeStale (mai ricostruito da zero in `nearbyPeople`, altrimenti
  // si perderebbe il vantaggio) -- stessa idea del partizionamento per
  // fascia già usato in `HotspotStore.detectAndRefresh`, qui però tenuto nel
  // tempo invece che ricalcolato una tantum. Riduce `nearbyPeople` da uno
  // scan O(sessioni totali online) a uno scan O(densità locale): con N
  // persone online ma sparse, non serve più confrontare ognuna con tutte le
  // altre N-1 ad ogni ricalcolo.
  static const double _gridBandMeters = 100;
  static const double _metersPerDegreeLat = 111320;

  final DateTime Function() _now;
  final Map<String, Session> _sessions = {};
  final Map<int, Set<String>> _sessionIdsByLatBand = {};
  final Map<String, int> _latBandOfSession = {};
  Timer? _autoPurgeTimer;

  int _latBandFor(double lat) => (lat * _metersPerDegreeLat / _gridBandMeters).floor();

  void _indexPosition(String sessionId, double lat) {
    final band = _latBandFor(lat);
    if (_latBandOfSession[sessionId] == band) return;

    _deindexPosition(sessionId);
    _sessionIdsByLatBand.putIfAbsent(band, () => {}).add(sessionId);
    _latBandOfSession[sessionId] = band;
  }

  void _deindexPosition(String sessionId) {
    final band = _latBandOfSession.remove(sessionId);
    if (band == null) return;

    final bucket = _sessionIdsByLatBand[band];
    bucket?.remove(sessionId);
    if (bucket != null && bucket.isEmpty) _sessionIdsByLatBand.remove(band);
  }

  /// Gli id delle sessioni **candidate** ad essere entro `radiusMeters` da
  /// `lat` — filtra solo per fascia di latitudine (ignora la longitudine,
  /// stesso limite di `HotspotStore._latitudeBand`: chi condivide la
  /// latitudine ma è lontanissimo in longitudine resta candidato, scartato
  /// poi dall'Haversine esatto). Una sovrastima sicura, mai un difetto: chi
  /// torna qui va comunque riverificato con `distanceMeters`, questo serve
  /// solo a non dover scandire ogni sessione online per scoprirlo.
  Set<String> _sessionIdsNear(double lat, double radiusMeters) {
    final centerBand = _latBandFor(lat);
    // +1 di margine di sicurezza oltre al rapporto esatto.
    final bandSpan = (radiusMeters / _gridBandMeters).ceil() + 1;

    final ids = <String>{};
    for (var band = centerBand - bandSpan; band <= centerBand + bandSpan; band++) {
      final bucket = _sessionIdsByLatBand[band];
      if (bucket != null) ids.addAll(bucket);
    }
    return ids;
  }

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
    String deviceId = '',
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
        deviceId: deviceId,
      );
      _indexPosition(sessionId, lat);
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
    existing.deviceId = deviceId;
    _indexPosition(sessionId, lat);
  }

  /// Rimuove `sessionId` dallo store — equivalente del bottone End (o della
  /// chiusura del WebSocket): chi esce non deve più comparire nella lista
  /// di nessuno.
  void remove(String sessionId) {
    _sessions.remove(sessionId);
    _deindexPosition(sessionId);
  }

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
    for (final id in staleIds) {
      _sessions.remove(id);
      _deindexPosition(id);
    }
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

  /// Tutte le sessioni online — usato da `HotspotStore.detectAndRefresh`
  /// (via `ConnectionHub`) per cercare cluster tra le posizioni note, senza
  /// dover esporre la mappa interna.
  Iterable<Session> get allSessions => _sessions.values;

  /// Persone entro [radiusMeters] da `sessionId` (o entro un hotspot attivo
  /// di cui entrambi fanno parte — vedi [HotspotStore] — anche se la
  /// distanza diretta tra i due supera [radiusMeters]), con probabilità
  /// d'incontro già calcolata. Ritorna `null` se `sessionId` non ha ancora
  /// mandato una posizione (deve prima chiamare `POST /presence`).
  ///
  /// Non scandisce più *tutte* le sessioni online: raccoglie prima i
  /// candidati dall'indice spaziale (vicini a `sessionId` per il raggio
  /// base, più chiunque sia vicino a un hotspot attivo di cui `sessionId`
  /// potrebbe far parte — vedi `_sessionIdsNear`), poi applica su
  /// quell'insieme, tipicamente molto più piccolo, le stesse identiche
  /// regole di sempre (genere/raggio-o-hotspot/permanenza). Una sovrastima
  /// dei candidati è innocua (viene comunque scartata dai controlli esatti
  /// sotto); un difetto no — per questo l'hotspot check usa
  /// `Hotspot.exitRadiusMeters` (il raggio più largo, con isteresi) e non
  /// quello base.
  ///
  /// **Paywall**: se `sessionId` non ha sbloccato l'accesso (vedi
  /// [PaywallStore], per il suo `Session.deviceId`), il terzo più vicino
  /// delle persone qui sotto viene rimandato con `selfieBase64` vuoto
  /// (stessa regola — un terzo, i più vicini, minimo 2 gratis — di
  /// `GetLockedNearbyPeopleUseCase` nel client Flutter, ma qui è dove viene
  /// davvero **applicata**: il client la duplica solo per decidere come
  /// disegnare la lista, non più per decidere cosa arriva sul dispositivo —
  /// altrimenti un client modificato potrebbe leggere i selfie veri senza
  /// aver mai pagato, dato che li avrebbe comunque ricevuti tutti).
  List<NearbyPersonResult>? nearbyPeople({
    required String sessionId,
    required double radiusMeters,
    HotspotStore? hotspotStore,
    PaywallStore? paywallStore,
  }) {
    final me = _sessions[sessionId];
    if (me == null) return null;

    final hotspots = hotspotStore ?? HotspotStore.instance;
    final paywall = paywallStore ?? PaywallStore.instance;
    final now = _now();
    final results = <NearbyPersonResult>[];

    final candidateIds = _sessionIdsNear(me.lat, radiusMeters);
    for (final hotspot in hotspots.active) {
      // Sovrastima deliberata: non sappiamo ancora (senza toccare lo stato
      // interno di HotspotStore) se `me` è davvero membro con isteresi, solo
      // che potrebbe esserlo -- il controllo esatto, `sharesAnyActiveHotspot`
      // qui sotto, decide per davvero.
      if (distanceMeters(me.lat, me.lng, hotspot.centerLat, hotspot.centerLng) <=
          Hotspot.exitRadiusMeters) {
        candidateIds.addAll(
          _sessionIdsNear(hotspot.centerLat, Hotspot.exitRadiusMeters),
        );
      }
    }
    candidateIds.remove(sessionId);

    for (final otherId in candidateIds) {
      final other = _sessions[otherId];
      if (other == null) continue; // difesa: indice e mappa mai disallineati per costruzione, ma economico da controllare.

      // "Il genere che l'utente vuole vedere in Vicinanze" — filtro a senso
      // unico sulla mia preferenza, non serve reciprocità.
      if (me.genderPreference != 'everyone' &&
          other.gender != me.genderPreference) {
        continue;
      }

      final distance = distanceMeters(me.lat, me.lng, other.lat, other.lng);
      final direct = distance <= radiusMeters;
      final viaHotspot =
          !direct &&
          hotspots.sharesAnyActiveHotspot(
            me.sessionId,
            me.lat,
            me.lng,
            other.sessionId,
            other.lat,
            other.lng,
          );
      if (!direct && !viaHotspot) continue;

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

    final isUnlocked = me.deviceId.isNotEmpty && paywall.isUnlocked(me.deviceId);
    return _withPaywallVisibility(results, isUnlocked: isUnlocked);
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

// Stessa identica regola di `GetLockedNearbyPeopleUseCase` nel client
// Flutter (lib/features/paywall/domain/usecases/) -- se una cambia, va
// cambiata anche l'altra. Tenuta qui come funzione libera (non un metodo di
// `SessionStore`) perché è pura: nessuno stato, solo la lista in ingresso.
const _paywallFreeFraction = 1 / 3;
const _paywallMinFreeCount = 2;

/// Un terzo delle persone più **lontane** resta sempre gratis (chi è più
/// vicino, più probabile da incontrare davvero, è il contenuto a
/// pagamento) -- minimo [_paywallMinFreeCount] anche su liste corte, dove
/// un terzo arrotonderebbe a 0 o 1. Se sbloccato, o la lista è vuota,
/// ritorna `people` invariata. Altrimenti ritorna una nuova lista con lo
/// stesso ordine, ma `selfieBase64` svuotato per chi non è nel terzo
/// gratis -- `distanceMeters`/`meetingChance` restano sempre presenti (mai
/// stati sensibili, servono al client per decidere come disegnare la
/// lista).
List<NearbyPersonResult> _withPaywallVisibility(
  List<NearbyPersonResult> people, {
  required bool isUnlocked,
}) {
  if (isUnlocked || people.isEmpty) return people;

  final byFarthestFirst = [...people]
    ..sort((a, b) => b.distanceMeters.compareTo(a.distanceMeters));
  final freeCount = math.min(
    people.length,
    math.max(
      (people.length * _paywallFreeFraction).floor(),
      _paywallMinFreeCount,
    ),
  );
  final freeIds = byFarthestFirst
      .take(freeCount)
      .map((p) => p.sessionId)
      .toSet();

  return [
    for (final person in people)
      if (freeIds.contains(person.sessionId))
        person
      else
        NearbyPersonResult(
          sessionId: person.sessionId,
          distanceMeters: person.distanceMeters,
          meetingChance: person.meetingChance,
          selfieBase64: '',
        ),
  ];
}
