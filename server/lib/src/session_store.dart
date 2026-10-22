import 'dart:math' as math;

import 'package:threemojo_server/src/geo.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/meeting_chance.dart';
import 'package:threemojo_server/src/presence_profile.dart';
import 'package:threemojo_server/src/paywall_store.dart';

/// Una persona online: la sua ultima posizione accettata e la sua
/// **ancora** — il punto in cui è "ferma", da cui si misurano **tutte** le
/// distanze verso le altre persone (vedi [SessionStore.nearbyPeople]).
///
/// **L'ancora**: nasce con la sessione (o con uno spostamento confermato,
/// sotto) e si chiama "ancora" perché poi non segue più le letture.
/// - **Riscaldamento** (il primo [visibilityThresholdMinutes] minuto da
///   [arrivedAt], in cui la persona non vede nessuno e nessuno la vede):
///   l'ancora è la mediana, coordinata per coordinata, delle letture
///   raccolte da [arrivedAt] ([anchorFixes]) — così un primo fix GPS
///   sbagliato di 50 m non resta il riferimento per tutta la sosta.
/// - **Dopo il riscaldamento** l'ancora è **congelata**: le letture entro
///   [SessionStore.stationarityRadiusMeters] non la spostano più. Le
///   distanze tra due persone ferme restano quindi identiche finché una
///   delle due non si sposta davvero — chi muove la propria posizione (anche
///   con un GPS falso) a piccoli passi non ottiene nessun "campione" nuovo.
/// - **Spostamento confermato**: per [SessionStore.confirmMovementReadings]
///   letture di fila la posizione stimata — la mediana delle ultime
///   [SessionStore.recentFixesForMovement] letture ([recentFixes]), non la
///   singola lettura — è oltre [SessionStore.stationarityRadiusMeters]
///   dall'ancora (vedi [consecutiveAwayReadings]): uno o due fix sbagliati
///   di fila, tipici al chiuso, non bastano. Allora [arrivedAt] riparte da
///   zero e l'ancora riparte dalle letture "lontane" che lo hanno
///   confermato: per un minuto la persona sparisce per gli altri **e** la
///   sua lista è vuota.
class Session {
  Session({
    required this.sessionId,
    required this.lat,
    required this.lng,
    required this.arrivedAt,
    required this.lastSeen,
    this.profile = PresenceProfile.anonymous,
    this.selfieBase64 = '',
    this.unlockToken = '',
  }) : anchorLat = lat,
       anchorLng = lng,
       lastPositionAt = arrivedAt,
       anchorFixes = [(lat, lng)],
       recentFixes = [(lat, lng)];

  final String sessionId;

  /// Ultima posizione accettata, grezza. Serve al controllo di velocità e
  /// al rilevamento degli hotspot (`HotspotStore.detectAndRefresh`), **mai**
  /// alle distanze tra persone: quelle usano l'ancora.
  double lat;
  double lng;

  /// L'ancora (vedi la doc della classe): il punto da cui si misurano le
  /// distanze verso gli altri e da cui si decide se la persona si è mossa.
  double anchorLat;
  double anchorLng;

  /// Le letture da cui si calcola l'ancora durante il riscaldamento (al
  /// più [SessionStore.maxAnchorFixes], le più recenti). Dopo il
  /// riscaldamento non cresce più.
  final List<(double, double)> anchorFixes;

  /// Le letture con cui la posizione stimata è risultata oltre
  /// [SessionStore.stationarityRadiusMeters] dall'ancora, non ancora
  /// confermate come uno spostamento: se lo diventano, sono il punto di
  /// partenza della nuova ancora.
  final List<(double, double)> pendingAwayFixes = [];

  /// Le ultime [SessionStore.recentFixesForMovement] letture accettate: la
  /// loro mediana è la posizione con cui si decide se la persona si sta
  /// allontanando dall'ancora — un fix isolato sbagliato non la sposta.
  final List<(double, double)> recentFixes;

  /// Quante letture di fila sono risultate oltre
  /// [SessionStore.stationarityRadiusMeters] dall'ancora attuale, senza
  /// ancora essere confermate come un vero spostamento.
  int consecutiveAwayReadings = 0;

  DateTime arrivedAt;

  /// Ultimo messaggio ricevuto da questa sessione (qualsiasi tipo, non solo
  /// la presenza) — vedi [SessionStore.touch].
  DateTime lastSeen;

  /// Quando è stata accettata l'ultima posizione: serve al controllo di
  /// velocità e al limite di frequenza ([SessionStore.minPositionInterval])
  /// di [SessionStore.upsertPosition].
  DateTime lastPositionAt;

  /// `false` durante il periodo di grazia dopo una caduta del socket (vedi
  /// `SessionLifecycle`): la sessione esiste ancora (stesso id, stessa
  /// permanenza, stesse richieste e match) ma non compare a nessuno in
  /// "Vicinanze" finché non si riconnette.
  bool connected = true;

  /// Genere, chi cerca, intento, lingue, "mostra il mio genere" — già
  /// validati (`PresenceProfile.fromJson`). **Fissati alla nascita della
  /// sessione**: le presenze successive non li cambiano. Altrimenti chi vuole
  /// scoprire la preferenza di qualcuno potrebbe cambiare il proprio genere a
  /// sessione aperta e vedere quando compare/scompare (vedi anche il limite
  /// ai nuovi Start in `NewSessionRateLimiter`).
  final PresenceProfile profile;

  /// Il selfie della sessione in base64, già controllato e ripulito dai
  /// metadati (`SelfieValidator`) — il server non ne guarda i pixel, lo
  /// tiene solo per ridistribuirlo a chi lo vede in "Vicinanze". Fissato
  /// alla prima presenza che lo porta, come il profilo: le successive non lo
  /// cambiano (e non serve rimandarlo).
  String selfieBase64;

  /// Il token di sblocco a pagamento (`PaywallStore.issueUnlockToken`),
  /// mandato con la presenza solo da chi ha pagato e solo finché vale (2
  /// ore). Stringa vuota per chi non ha pagato — trattata come "non
  /// sbloccato", mai come errore. Non identifica il dispositivo: scaduto,
  /// non collega più nulla.
  String unlockToken;
}

/// Una persona vicina già pronta per il client: stadio di probabilità
/// d'incontro, selfie (se non bloccato dal paywall) e il flag [locked] già
/// calcolati qui. **Nessuna distanza** verso il client: [distanceMeters]
/// resta interna (serve solo all'ordine per fasce e al paywall) — un
/// numero preciso a ogni push, insieme a qualche spostamento, basterebbe a
/// trilaterare la posizione di una persona. Del profilo solo ciò che la persona mostra:
/// intento, lingue e il genere solo se ha scelto di renderlo visibile —
/// **mai** chi cerca.
class NearbyPersonResult {
  NearbyPersonResult({
    required this.sessionId,
    required this.distanceMeters,
    required this.meetingChance,
    required this.selfieBase64,
    this.locked = false,
    this.intent,
    this.languages = const [],
    this.visibleGender,
  });

  /// Id **interno**: non va mai nel JSON così com'è, il client riceve uno
  /// pseudonimo per osservatore (vedi `Pseudonyms`, `ConnectionHub`).
  final String sessionId;

  /// Da ancora ad ancora. Solo per uso interno (ordine per fasce, paywall):
  /// mai serializzata.
  final double distanceMeters;
  final MeetingChance meetingChance;
  final String selfieBase64;

  /// Dietro il paywall per chi guarda: [selfieBase64] è vuoto.
  final bool locked;
  final String? intent;
  final List<String> languages;
  final String? visibleGender;

  /// Il JSON per chi guarda, con [personId] = lo pseudonimo con cui quella
  /// persona vede questa. Il selfie c'è solo se non è bloccato.
  Map<String, dynamic> toJson({required String personId}) => {
    'personId': personId,
    'meetingChance': meetingChance.name,
    'locked': locked,
    if (!locked && selfieBase64.isNotEmpty) 'selfieBase64': selfieBase64,
    if (intent != null) 'intent': intent,
    if (languages.isNotEmpty) 'languages': languages,
    if (visibleGender != null) 'gender': visibleGender,
  };
}

/// Esito di [SessionStore.upsertPosition].
enum PresenceOutcome {
  accepted,

  /// Coordinate non finite o fuori scala: scartata.
  invalidCoordinates,

  /// Salto fisicamente impossibile rispetto all'ultima posizione accettata
  /// (vedi [SessionStore.maxPlausibleSpeedMetersPerSecond]): scartata.
  implausibleMovement,

  /// Arrivata meno di [SessionStore.minPositionInterval] dopo l'ultima
  /// posizione accettata: la posizione è **ignorata** (in silenzio, nessun
  /// rifiuto al client), mentre token di sblocco e selfie mancante sono
  /// comunque presi. Non è un errore: il client può mandare posizioni più
  /// spesso (iOS ~1 al secondo), il server ne usa una ogni tanto.
  tooSoon,
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

  /// Al più una posizione **utile** ogni tanto per sessione: le presenze
  /// che arrivano prima sono ignorate ([PresenceOutcome.tooSoon]). Il
  /// client Android manda una posizione ogni 60 s, iOS a ogni cambiamento
  /// (anche ~1 al secondo): 10 s bastano a seguire chi si sposta davvero
  /// (uno spostamento si conferma in 3 letture, quindi in ~20-30 s su iOS)
  /// e tolgono a chi falsifica il GPS la possibilità di "sondare" a raffica.
  static const Duration minPositionInterval = Duration(seconds: 10);

  /// Quante letture (le più recenti) entrano nella mediana dell'ancora
  /// durante il riscaldamento: a una lettura ogni [minPositionInterval],
  /// copre tutto il primo minuto.
  static const int maxAnchorFixes = 8;

  /// Quante letture recenti entrano nella posizione stimata con cui si
  /// decide se ci si allontana dall'ancora (la loro mediana, vedi
  /// [Session]). Con 3, un fix isolato sbagliato non sposta mai la stima, e
  /// un vero spostamento si conferma in 3 letture accettate (~20-30 s su
  /// iOS, 2-3 minuti su Android, che manda una posizione al minuto).
  ///
  /// Perché la mediana (e l'ancora mediana nel riscaldamento): ora che uno
  /// spostamento confermato svuota per un minuto anche la lista di chi si
  /// sposta, un reset "finto" costa di più. Simulando un telefono fermo al
  /// chiuso con errore di 20-50 m in direzione casuale a ogni lettura (caso
  /// pessimo: errori indipendenti), una lettura ogni 10 s: ~20 reset l'ora
  /// con la sola regola delle 2 letture grezze, ~5 con l'ancora mediana,
  /// ~1 con anche la stima mediana; con errore di 20-40 m, ~0,1 l'ora.
  static const int recentFixesForMovement = 3;

  /// Larghezza delle fasce di distanza con cui è ordinata la lista
  /// "vicinanze" (vedi [SessionStore.nearbyPeople]): dentro una fascia
  /// l'ordine è fisso per osservatore e non dice chi è più vicino. Simile
  /// all'errore tipico del GPS (5-20 m, di più al chiuso): un ordine più
  /// fine di così sarebbe comunque in buona parte rumore.
  static const double rankBandMeters = 25;

  /// Controllo di velocità sulle presenze: tra due posizioni accettate non
  /// ci si può spostare più di `velocità × tempo trascorso +`
  /// [positionJumpSlackMeters]. Serve contro chi "teletrasporta" la propria
  /// posizione per sondare dove si trova qualcuno (entra/esce dal raggio).
  /// Si auto-ripara: una lettura scartata non aggiorna il riferimento,
  /// quindi col passare del tempo un vero spostamento lungo (es. il primo
  /// fix GPS dopo uno approssimato) viene comunque accettato.
  static const double maxPlausibleSpeedMetersPerSecond = 50;

  /// Tolleranza per l'errore del GPS (salti di qualche centinaio di metri
  /// al chiuso sono normali) — vedi [maxPlausibleSpeedMetersPerSecond].
  static const double positionJumpSlackMeters = 250;

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

  int _latBandFor(double lat) =>
      (lat * _metersPerDegreeLat / _gridBandMeters).floor();

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
    for (
      var band = centerBand - bandSpan;
      band <= centerBand + bandSpan;
      band++
    ) {
      final bucket = _sessionIdsByLatBand[band];
      if (bucket != null) ids.addAll(bucket);
    }
    return ids;
  }

  /// Aggiorna la posizione di `sessionId` (creando la sessione alla prima
  /// presenza) e la sua ancora (vedi [Session]). Se la posizione stimata
  /// (mediana delle ultime [recentFixesForMovement] letture) risulta oltre
  /// [stationarityRadiusMeters] dall'ancora, non resetta subito la
  /// stazionarietà: serve che questo capiti per [confirmMovementReadings]
  /// letture di fila prima di considerarlo un vero spostamento ("è arrivata
  /// altrove", si riparte da zero) — un balzo GPS isolato che poi torna
  /// vicino non conta.
  ///
  /// Profilo e selfie sono fissati alla nascita della sessione: per una
  /// sessione esistente `profile` è ignorato e `selfieBase64` viene preso
  /// solo se finora non ce n'era uno. Posizioni troppo ravvicinate,
  /// coordinate non valide o salti impossibili vengono scartati (vedi
  /// [PresenceOutcome]) senza toccare la posizione.
  PresenceOutcome upsertPosition({
    required String sessionId,
    required double lat,
    required double lng,
    PresenceProfile profile = PresenceProfile.anonymous,
    String selfieBase64 = '',
    String unlockToken = '',
  }) {
    if (!isValidCoordinate(lat, lng)) return PresenceOutcome.invalidCoordinates;

    final now = _now();
    final existing = _sessions[sessionId];

    if (existing == null) {
      _sessions[sessionId] = Session(
        sessionId: sessionId,
        lat: lat,
        lng: lng,
        arrivedAt: now,
        lastSeen: now,
        profile: profile,
        selfieBase64: selfieBase64,
        unlockToken: unlockToken,
      );
      _indexPosition(sessionId, lat);
      return PresenceOutcome.accepted;
    }

    existing.lastSeen = now;
    existing.unlockToken = unlockToken;
    if (existing.selfieBase64.isEmpty && selfieBase64.isNotEmpty) {
      existing.selfieBase64 = selfieBase64;
    }

    final sinceLastPosition = now.difference(existing.lastPositionAt);
    if (sinceLastPosition < minPositionInterval) return PresenceOutcome.tooSoon;

    final secondsSinceLastPosition = sinceLastPosition.inMilliseconds / 1000;
    final jump = distanceMeters(existing.lat, existing.lng, lat, lng);
    if (jump >
        maxPlausibleSpeedMetersPerSecond * secondsSinceLastPosition +
            positionJumpSlackMeters) {
      return PresenceOutcome.implausibleMovement;
    }

    final fix = (lat, lng);
    existing.recentFixes.add(fix);
    if (existing.recentFixes.length > recentFixesForMovement) {
      existing.recentFixes.removeAt(0);
    }
    final looksAway =
        distanceMeters(
          existing.anchorLat,
          existing.anchorLng,
          _median(existing.recentFixes.map((f) => f.$1)),
          _median(existing.recentFixes.map((f) => f.$2)),
        ) >
        stationarityRadiusMeters;
    if (looksAway) {
      existing.consecutiveAwayReadings++;
      existing.pendingAwayFixes.add(fix);
    } else {
      existing.consecutiveAwayReadings = 0;
      existing.pendingAwayFixes.clear();
    }

    if (existing.consecutiveAwayReadings >= confirmMovementReadings) {
      // Arrivata altrove: si riparte da zero, e la nuova ancora parte dalle
      // letture che hanno confermato lo spostamento.
      existing.anchorFixes
        ..clear()
        ..addAll(existing.pendingAwayFixes);
      existing.pendingAwayFixes.clear();
      existing.consecutiveAwayReadings = 0;
      existing.arrivedAt = now;
      _refreshAnchor(existing);
    } else if (!looksAway && _isWarmingUp(existing, now)) {
      existing.anchorFixes.add(fix);
      if (existing.anchorFixes.length > maxAnchorFixes) {
        existing.anchorFixes.removeAt(0);
      }
      _refreshAnchor(existing);
    }

    existing.lat = lat;
    existing.lng = lng;
    existing.lastPositionAt = now;
    _indexPosition(sessionId, existing.anchorLat);
    return PresenceOutcome.accepted;
  }

  /// Ancora non ancora congelata: il primo [visibilityThresholdMinutes]
  /// minuto da `arrivedAt`, in cui la persona è invisibile e non vede
  /// nessuno — perfezionarla qui non rivela niente a nessuno.
  bool _isWarmingUp(Session session, DateTime now) =>
      now.difference(session.arrivedAt).inMinutes < visibilityThresholdMinutes;

  /// L'ancora = mediana, coordinata per coordinata, di `anchorFixes`: un
  /// singolo fix sbagliato di decine di metri non la sposta.
  void _refreshAnchor(Session session) {
    session
      ..anchorLat = _median(session.anchorFixes.map((f) => f.$1))
      ..anchorLng = _median(session.anchorFixes.map((f) => f.$2));
  }

  static double _median(Iterable<double> values) {
    final sorted = values.toList()..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  /// `true` se `sessionId` ha già mandato una presenza (anche se ora è nel
  /// periodo di grazia).
  bool contains(String sessionId) => _sessions.containsKey(sessionId);

  /// `true` se `sessionId` esiste ed è connessa ora (non nel periodo di
  /// grazia): l'unico caso in cui può ricevere una richiesta d'incontro.
  bool isOnline(String sessionId) => _sessions[sessionId]?.connected ?? false;

  /// Segna la sessione come connessa o no (periodo di grazia, vedi
  /// `SessionLifecycle`). Non connessa = invisibile a tutti in "Vicinanze",
  /// ma con stato, permanenza e richieste intatti.
  void setConnected(String sessionId, {required bool connected}) {
    _sessions[sessionId]?.connected = connected;
  }

  /// Registra che `sessionId` si è fatta viva (qualsiasi messaggio).
  void touch(String sessionId) {
    _sessions[sessionId]?.lastSeen = _now();
  }

  /// Rimuove `sessionId` dallo store — alla fine della sessione (End, fine
  /// del periodo di grazia, sessione silenziosa troppo a lungo: vedi
  /// `SessionLifecycle.endNow`): chi esce non deve più comparire nella lista
  /// di nessuno.
  void remove(String sessionId) {
    _sessions.remove(sessionId);
    _deindexPosition(sessionId);
  }

  /// Il selfie di `sessionId`, così com'è arrivato dal client — usato da
  /// `ConnectionHub` per arricchire le richieste d'incontro con una foto
  /// sempre fresca, senza doverla conservare nella richiesta stessa.
  /// `null` se la sessione non è (più) online.
  String? selfieBase64For(String sessionId) =>
      _sessions[sessionId]?.selfieBase64;

  /// Il token di sblocco che `sessionId` ha mandato con l'ultima presenza
  /// (stringa vuota se non ha pagato), `null` se la sessione non esiste.
  String? unlockTokenFor(String sessionId) => _sessions[sessionId]?.unlockToken;

  /// Il profilo di sessione di `sessionId`, per mostrare nelle richieste
  /// d'incontro ciò che la persona ha scelto di rendere visibile. `null` se
  /// la sessione non è (più) online.
  PresenceProfile? profileFor(String sessionId) =>
      _sessions[sessionId]?.profile;

  /// Tutte le sessioni connesse ora (non quelle nel periodo di grazia) —
  /// usato da `HotspotStore.detectAndRefresh` (via `ConnectionHub`) per
  /// cercare cluster tra le posizioni note, senza dover esporre la mappa
  /// interna.
  Iterable<Session> get allSessions =>
      _sessions.values.where((session) => session.connected);

  /// Persone entro [radiusMeters] da `sessionId` (o entro un hotspot attivo
  /// di cui entrambi fanno parte — vedi [HotspotStore] — anche se la
  /// distanza diretta tra i due supera [radiusMeters]), con probabilità
  /// d'incontro già calcolata, **ordinate per fasce di distanza** (sotto).
  /// Ritorna `null` se `sessionId` non ha ancora mandato una presenza sul
  /// WebSocket. Chi è nel periodo di grazia (non connesso) non compare a
  /// nessuno.
  ///
  /// **Anche chi guarda dev'essere fermo**: finché `sessionId` non è ferma
  /// da [visibilityThresholdMinutes] minuto (lo stesso tempo che serve per
  /// comparire agli altri) la lista è **vuota** — appena arrivata, e di
  /// nuovo dopo ogni spostamento confermato. E le distanze vanno **da
  /// ancora ad ancora** (vedi [Session]), mai dall'ultima lettura grezza:
  /// prima, chi falsificava il GPS poteva camminare a piccoli passi sul
  /// bordo del cerchio e, con un sì/no a ogni ricalcolo, localizzare
  /// chiunque a 10-30 m in meno di un minuto. Ora ogni "campione" costa uno
  /// spostamento confermato più un minuto di attesa.
  ///
  /// **Ordine per fasce**: dalla fascia di [rankBandMeters] più vicina alla
  /// più lontana; dentro una fascia l'ordine è fisso per osservatore (un
  /// hash della coppia, non la distanza), così la posizione in lista non
  /// rivela chi è più vicino di pochi metri. Il paywall (sotto) resta
  /// invece calcolato sulla distanza esatta tra le ancore.
  ///
  /// Non scandisce *tutte* le sessioni online: raccoglie prima i candidati
  /// dall'indice spaziale (vicini a `sessionId` per il raggio base, più
  /// chiunque sia vicino a un hotspot attivo di cui `sessionId` potrebbe far
  /// parte — vedi `_sessionIdsNear`), poi applica su quell'insieme,
  /// tipicamente molto più piccolo, le stesse identiche regole di sempre
  /// (genere/raggio-o-hotspot/permanenza). Una sovrastima dei candidati è
  /// innocua (viene comunque scartata dai controlli esatti sotto); un
  /// difetto no — per questo l'hotspot check usa `Hotspot.exitRadiusMeters`
  /// (il raggio più largo, con isteresi) e non quello base.
  ///
  /// **Paywall** (applicato solo qui, il client non lo ricalcola): se
  /// `sessionId` non ha sbloccato l'accesso (vedi [PaywallStore], per il suo
  /// `Session.unlockToken`), resta gratis solo **un terzo delle persone più
  /// lontane** (minimo 2); i **due terzi più vicini** — i più probabili da
  /// incontrare davvero, cioè il contenuto a pagamento — arrivano con
  /// `locked: true` e senza selfie. Il client riceve solo il flag già
  /// pronto: un client modificato non può leggere i selfie bloccati, perché
  /// non gli arrivano mai.
  List<NearbyPersonResult>? nearbyPeople({
    required String sessionId,
    required double radiusMeters,
    HotspotStore? hotspotStore,
    PaywallStore? paywallStore,
  }) {
    final me = _sessions[sessionId];
    if (me == null) return null;

    final now = _now();
    if (_isWarmingUp(me, now)) return <NearbyPersonResult>[];

    final hotspots = hotspotStore ?? HotspotStore.instance;
    final paywall = paywallStore ?? PaywallStore.instance;
    final results = <NearbyPersonResult>[];

    final candidateIds = _sessionIdsNear(me.anchorLat, radiusMeters);
    for (final hotspot in hotspots.active) {
      // Sovrastima deliberata: non sappiamo ancora (senza toccare lo stato
      // interno di HotspotStore) se `me` è davvero membro con isteresi, solo
      // che potrebbe esserlo -- il controllo esatto, `sharesAnyActiveHotspot`
      // qui sotto, decide per davvero.
      if (distanceMeters(
            me.anchorLat,
            me.anchorLng,
            hotspot.centerLat,
            hotspot.centerLng,
          ) <=
          Hotspot.exitRadiusMeters) {
        candidateIds.addAll(
          _sessionIdsNear(hotspot.centerLat, Hotspot.exitRadiusMeters),
        );
      }
    }
    candidateIds.remove(sessionId);

    for (final otherId in candidateIds) {
      final other = _sessions[otherId];
      // Difesa: indice e mappa mai disallineati per costruzione, ma
      // economico da controllare.
      if (other == null) continue;
      if (!other.connected) continue; // nel periodo di grazia: invisibile.

      // Matching reciproco: ci si vede solo se ognuno rientra in ciò che
      // cerca l'altro (vedi `PresenceProfile.mutuallyCompatible`).
      if (!PresenceProfile.mutuallyCompatible(me.profile, other.profile)) {
        continue;
      }

      final distance = distanceMeters(
        me.anchorLat,
        me.anchorLng,
        other.anchorLat,
        other.anchorLng,
      );
      final direct = distance <= radiusMeters;
      final viaHotspot =
          !direct &&
          hotspots.sharesAnyActiveHotspot(
            me.sessionId,
            me.anchorLat,
            me.anchorLng,
            other.sessionId,
            other.anchorLat,
            other.anchorLng,
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
          intent: other.profile.intent,
          languages: other.profile.languages,
          visibleGender: other.profile.visibleGender,
        ),
      );
    }

    int band(NearbyPersonResult p) =>
        (p.distanceMeters / rankBandMeters).floor();
    int tiebreak(NearbyPersonResult p) =>
        Object.hash(me.sessionId, p.sessionId);
    results.sort((a, b) {
      final byBand = band(a).compareTo(band(b));
      if (byBand != 0) return byBand;
      final byTiebreak = tiebreak(a).compareTo(tiebreak(b));
      if (byTiebreak != 0) return byTiebreak;
      return a.sessionId.compareTo(b.sessionId);
    });
    final isUnlocked =
        me.unlockToken.isNotEmpty && paywall.isUnlocked(me.unlockToken);
    return _withPaywallVisibility(results, isUnlocked: isUnlocked);
  }

  /// Solo per debug locale: tutte le sessioni in memoria, senza filtri di
  /// raggio/genere/tempo di permanenza — per verificare "chi risulta al
  /// server" indipendentemente da cosa vede un client specifico. Niente
  /// posizione grezza, distanze, selfie, genere né preferenza (insieme
  /// lasciano dedurre l'orientamento sessuale o, le distanze a coppie,
  /// triangolare chiunque): solo ciò che serve a controllare che una
  /// sessione sia arrivata e sia viva.
  List<Map<String, dynamic>> debugSnapshot() {
    final now = _now();
    return _sessions.values
        .map(
          (s) => {
            'sessionId': s.sessionId,
            'connected': s.connected,
            'dwellSeconds': now.difference(s.arrivedAt).inSeconds,
            'lastSeenSecondsAgo': now.difference(s.lastSeen).inSeconds,
          },
        )
        .toList();
  }
}

// Era duplicata in `GetLockedNearbyPeopleUseCase` nel client Flutter: ora il
// client riceve solo il flag `locked` già calcolato qui, e non la ricalcola
// più (due calcoli potevano divergere). Tenuta come funzione libera (non un
// metodo di `SessionStore`) perché è pura: nessuno stato, solo la lista in
// ingresso.
const _paywallFreeFraction = 1 / 3;
const _paywallMinFreeCount = 2;

/// Un terzo delle persone più **lontane** resta sempre gratis (chi è più
/// vicino, più probabile da incontrare davvero, è il contenuto a
/// pagamento) -- minimo [_paywallMinFreeCount] anche su liste corte, dove
/// un terzo arrotonderebbe a 0 o 1. Se sbloccato, o la lista è vuota,
/// ritorna `people` invariata. Altrimenti ritorna una nuova lista con lo
/// stesso ordine (per fasce), ma con `locked: true` e `selfieBase64` vuoto
/// per chi non è nel terzo gratis — `meetingChance` e ciò che la persona mostra del
/// profilo restano presenti (mai stati sensibili, danno un motivo per
/// sbloccare la foto).
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
          locked: true,
          intent: person.intent,
          languages: person.languages,
          visibleGender: person.visibleGender,
        ),
  ];
}
