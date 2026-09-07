import 'package:threemojo_server/src/geo.dart';
import 'package:threemojo_server/src/session_store.dart';

/// Una zona d'incontro rilevata dal server: il centro (media delle posizioni
/// di chi l'ha formata) e per quanto resta attiva. Non tiene traccia di
/// *chi* l'ha formata — una volta creato, un hotspot è solo un punto e una
/// scadenza, riconfermata mentre la zona resta popolata (vedi
/// `HotspotStore.detectAndRefresh`).
class Hotspot {
  Hotspot({
    required this.centerLat,
    required this.centerLng,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Mutabili apposta: se il gruppo che sostiene l'hotspot si è ridotto al
  /// minimo e si è spostato verso il bordo, `detectAndRefresh` sposta questi
  /// due campi sul centroide del gruppo attuale invece di lasciarlo ancorato
  /// a un punto ormai poco rappresentativo — vedi `HotspotStore.detectAndRefresh`.
  double centerLat;
  double centerLng;
  final DateTime createdAt;

  /// Mutabile apposta: rinnovare un hotspot ancora popolato estende questo
  /// campo sullo stesso oggetto (stesso centro o ricalcolato, vedi sopra),
  /// invece di crearne uno nuovo — vedi `HotspotStore.detectAndRefresh`.
  DateTime expiresAt;

  static const double radiusMeters = 200;

  /// Isteresi d'uscita: una volta dentro (a [radiusMeters]), serve
  /// allontanarsi oltre *questo* raggio più largo per uscire dalla
  /// visibilità — altrimenti chi sta esattamente sul bordo dei 200m
  /// entrerebbe/uscirebbe dalla lista "Vicinanze" a ogni piccola
  /// oscillazione GPS. Vedi `HotspotStore._isMember`.
  static const double exitRadiusMeters = radiusMeters * 1.2;

  /// Chi è attualmente "dentro" questo hotspot, con isteresi — aggiornato
  /// pigramente, sessione per sessione, da `HotspotStore._isMember` ad ogni
  /// `sharesAnyActiveHotspot` (istantaneo ad ogni broadcast, come il resto
  /// della visibilità — non aspetta il prossimo giro di
  /// `HotspotStore.detectAndRefresh`, che rimane responsabile solo di
  /// creare/rinnovare/far scadere l'hotspot in sé, non la membership).
  final Set<String> memberSessionIds = {};
}

/// Tiene in memoria le zone d'incontro attive — stesso pattern di
/// `SessionStore`/`EncounterStore`/`PaywallStore` (singleton in RAM, nessuna
/// persistenza, orologio iniettabile per i test).
///
/// **Regola di business**: quando ≥[minClusterSize] sessioni sono
/// reciprocamente entro [clusterRadiusMeters] l'una dall'altra, e ognuna è
/// *già*, per conto proprio, ferma da almeno [clusterMinDwellMinutes] minuti
/// (riusa `Session.arrivedAt`/il dwell già tenuto per ogni sessione — niente
/// nuovo timer di gruppo, niente identità da tracciare nel tempo: se cambia
/// chi c'è, la condizione si ricalcola da sola a ogni controllo), il centro
/// (media delle posizioni) diventa un hotspot per [lifetime] — dentro il suo
/// raggio, chiunque vede chiunque altro sia anch'esso dentro quel raggio,
/// anche se la distanza diretta tra i due supera [clusterRadiusMeters]
/// (vedi `SessionStore.nearbyPeople`, che consulta questo store). Possono
/// esistere più hotspot insieme in zone diverse, ma **mai due il cui cerchio
/// si sovrappone** — vedi `_wouldOverlapAnotherHotspot`, consultato sia alla
/// creazione sia quando un hotspot esistente si ricalcola.
class HotspotStore {
  HotspotStore._({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Solo per i test: un'istanza con orologio controllabile, invece del
  /// singleton condiviso con `DateTime.now()` reale.
  factory HotspotStore.withClock(DateTime Function() now) =>
      HotspotStore._(now: now);

  static final HotspotStore instance = HotspotStore._();

  static const int minClusterSize = 3;

  // Stesso valore del nuovo raggio base individuale (ConnectionHub.radiusMeters):
  // un hotspot nasce solo da persone già reciprocamente vicine con la regola
  // di oggi, non da un raggio di rilevamento indipendente.
  static const double clusterRadiusMeters = 100;

  // Più alta della soglia di MeetingChance.high (5 min, meeting_chance.dart)
  // apposta: un falso positivo qui costa più caro che sul dwell individuale
  // — non colora solo un profilo, allarga la visibilità per un intero
  // gruppo di persone. 5 minuti bastano a 3 sconosciuti fermi per caso allo
  // stesso semaforo/fermata/coda, senza che stia succedendo nulla di reale.
  static const int clusterMinDwellMinutes = 15;

  static const Duration lifetime = Duration(hours: 1);

  // Approssimazione grossolana (costante ovunque, non dipende dalla
  // latitudine) usata solo per raggruppare i candidati in `detectAndRefresh`
  // — non per decidere se qualcuno è davvero vicino: quello resta sempre
  // l'Haversine esatto di `distanceMeters`/`_allPairwiseWithin`.
  static const double _metersPerDegreeLat = 111320;

  final DateTime Function() _now;
  final List<Hotspot> _hotspots = [];

  /// Gli hotspot ancora attivi — scarta quelli scaduti prima di ritornare.
  List<Hotspot> get active {
    final now = _now();
    _hotspots.removeWhere((h) => now.isAfter(h.expiresAt));
    return List.unmodifiable(_hotspots);
  }

  /// true se esiste un hotspot attivo di cui **entrambe** le sessioni sono
  /// membre in questo momento (con isteresi — vedi `_isMember`) — non basta
  /// che ognuna sia dentro un hotspot qualsiasi, deve essere lo stesso per
  /// entrambe (altrimenti due persone in due zone calde diverse, dall'altra
  /// parte della città, risulterebbero visibili tra loro). Aggiorna
  /// `Hotspot.memberSessionIds` per entrambe le sessioni come effetto
  /// collaterale, così l'isteresi resta coerente alla chiamata successiva.
  bool sharesAnyActiveHotspot(
    String sessionId1,
    double lat1,
    double lng1,
    String sessionId2,
    double lat2,
    double lng2,
  ) {
    var shares = false;
    for (final hotspot in active) {
      final inFirst = _isMember(hotspot, sessionId1, lat1, lng1);
      final inSecond = _isMember(hotspot, sessionId2, lat2, lng2);
      if (inFirst && inSecond) shares = true;
    }
    return shares;
  }

  /// true se `sessionId` (in `lat`/`lng`) è "dentro" [hotspot] in questo
  /// momento, con isteresi: se non lo era, entra solo scendendo a
  /// [Hotspot.radiusMeters] o meno; se lo era già, resta dentro finché non
  /// supera [Hotspot.exitRadiusMeters] — così chi oscilla intorno al bordo
  /// per rumore GPS non compare/scompare dalla lista "Vicinanze" ad ogni
  /// controllo. Aggiorna `hotspot.memberSessionIds` di conseguenza.
  bool _isMember(Hotspot hotspot, String sessionId, double lat, double lng) {
    final distance = distanceMeters(
      lat,
      lng,
      hotspot.centerLat,
      hotspot.centerLng,
    );
    final wasMember = hotspot.memberSessionIds.contains(sessionId);
    final isMember = wasMember
        ? distance <= Hotspot.exitRadiusMeters
        : distance <= Hotspot.radiusMeters;
    if (isMember) {
      hotspot.memberSessionIds.add(sessionId);
    } else {
      hotspot.memberSessionIds.remove(sessionId);
    }
    return isMember;
  }

  /// true se un cerchio centrato in (lat,lng) si sovrapporrebbe al cerchio di
  /// un altro hotspot attivo (distanza tra i centri < la somma dei due raggi,
  /// cioè < il doppio di [Hotspot.radiusMeters], visto che tutti gli hotspot
  /// hanno lo stesso raggio) — due hotspot non possono mai esistere
  /// contemporaneamente se i loro cerchi si toccano. `excluding` esclude
  /// l'hotspot che si sta eventualmente ricalcolando dal confronto con sé
  /// stesso.
  bool _wouldOverlapAnotherHotspot(double lat, double lng, Hotspot? excluding) {
    for (final other in _hotspots) {
      if (identical(other, excluding)) continue;
      if (distanceMeters(lat, lng, other.centerLat, other.centerLng) <
          Hotspot.radiusMeters * 2) {
        return true;
      }
    }
    return false;
  }

  /// Chiamato a ogni broadcast (vedi `ConnectionHub.broadcastNearbyUpdates`):
  /// 1. Rinnovo: per ogni hotspot esistente, i "supporter" sono le sessioni
  ///    idonee entro il suo raggio che sono **anche** reciprocamente entro
  ///    [clusterRadiusMeters] tra loro (stesso vincolo della formazione —
  ///    altrimenti persone sparse fino a 400m l'una dall'altra, vicine solo
  ///    al vecchio centro, terrebbero in vita un hotspot che non potrebbe mai
  ///    essersi formato in quelle condizioni). Se sono ≥[minClusterSize]:
  ///    se il gruppo è ridotto proprio al minimo *e* si è spostato verso il
  ///    bordo (nessun supporter entro [clusterRadiusMeters] dal centro
  ///    attuale), il centro viene ricalcolato sul centroide dei supporter
  ///    attuali — altrimenti resta fermo. In entrambi i casi `expiresAt` si
  ///    estende. Se i supporter sono meno di [minClusterSize], l'hotspot non
  ///    viene rinnovato (scadrà da solo quando si supera `expiresAt`).
  /// 2. Scadenza: chi non è stato rinnovato ed è oltre `expiresAt` viene tolto.
  /// 3. Rilevamento: tra le sessioni idonee **vicine in latitudine** (vedi
  ///    partizionamento spaziale sotto — non tra tutte, ovunque si trovino),
  ///    cerca ogni gruppo di ≥[minClusterSize] reciprocamente entro
  ///    [clusterRadiusMeters] (tutte le coppie, non solo vicine a un centro)
  ///    e promuove il centroide a nuovo hotspot — a meno che il suo cerchio
  ///    si sovrapporrebbe a uno già esistente (rinnovato o no in questo
  ///    stesso giro), nel qual caso non viene creato: due hotspot non
  ///    coesistono mai sovrapposti.
  void detectAndRefresh(Iterable<Session> sessions) {
    final now = _now();
    final eligible = sessions
        .where(
          (s) =>
              now.difference(s.arrivedAt).inMinutes >= clusterMinDwellMinutes,
        )
        .toList();

    for (final hotspot in _hotspots) {
      final supporters = eligible
          .where(
            (s) =>
                distanceMeters(
                  s.lat,
                  s.lng,
                  hotspot.centerLat,
                  hotspot.centerLng,
                ) <=
                Hotspot.radiusMeters,
          )
          .toList();

      final isValidGroup =
          supporters.length >= minClusterSize &&
          _allPairwiseWithin(supporters, clusterRadiusMeters);
      if (!isValidGroup) continue;

      final onlyBareMinimum = supporters.length == minClusterSize;
      final noneNearCore = supporters.every(
        (s) =>
            distanceMeters(s.lat, s.lng, hotspot.centerLat, hotspot.centerLng) >
            clusterRadiusMeters,
      );
      if (onlyBareMinimum && noneNearCore) {
        final recenteredLat =
            supporters.map((s) => s.lat).reduce((a, b) => a + b) /
            supporters.length;
        final recenteredLng =
            supporters.map((s) => s.lng).reduce((a, b) => a + b) /
            supporters.length;
        // Non spostarlo se il nuovo punto farebbe sovrapporre il suo cerchio
        // a un altro hotspot attivo -- resta fermo al vecchio centro (viene
        // comunque rinnovato subito sotto) piuttosto che violare la regola
        // "due hotspot non coesistono mai sovrapposti".
        if (!_wouldOverlapAnotherHotspot(
          recenteredLat,
          recenteredLng,
          hotspot,
        )) {
          hotspot.centerLat = recenteredLat;
          hotspot.centerLng = recenteredLng;
        }
      }
      hotspot.expiresAt = now.add(lifetime);
    }
    _hotspots.removeWhere((h) => now.isAfter(h.expiresAt));

    // Partizionamento spaziale: raggruppa le sessioni idonee in fasce di
    // latitudine larghe quanto clusterRadiusMeters, così la ricerca
    // combinatoria (altrimenti O(n³) su TUTTE le sessioni idonee, ovunque si
    // trovino) si limita, fascia per fascia, a chi è già abbastanza vicino
    // in latitudine da poter davvero formare un triangolo — due sessioni in
    // fasce non adiacenti sono per forza più lontane di clusterRadiusMeters
    // (la larghezza di una fascia), quindi non potrebbero mai passare
    // `_allPairwiseWithin` insieme. Ogni tripla valida ha per forza tutti e
    // tre i membri entro una fascia di differenza l'uno dall'altro, quindi
    // esaminare (fascia-1, fascia, fascia+1) per ogni fascia occupata la
    // trova comunque — può essere esaminata più di una volta da fasce
    // diverse, ma `_wouldOverlapAnotherHotspot` già impedisce di crearla due
    // volte, quindi il lavoro in più è innocuo, solo ridondante.
    final byLatitudeBand = <int, List<Session>>{};
    for (final session in eligible) {
      byLatitudeBand
          .putIfAbsent(_latitudeBand(session.lat), () => [])
          .add(session);
    }

    for (final band in byLatitudeBand.keys) {
      final neighborhood = [
        ...?byLatitudeBand[band - 1],
        ...?byLatitudeBand[band],
        ...?byLatitudeBand[band + 1],
      ];

      for (final combo in _combinationsOfSize(neighborhood, minClusterSize)) {
        if (!_allPairwiseWithin(combo, clusterRadiusMeters)) continue;

        final centerLat =
            combo.map((s) => s.lat).reduce((a, b) => a + b) / combo.length;
        final centerLng =
            combo.map((s) => s.lng).reduce((a, b) => a + b) / combo.length;

        if (_wouldOverlapAnotherHotspot(centerLat, centerLng, null)) continue;

        _hotspots.add(
          Hotspot(
            centerLat: centerLat,
            centerLng: centerLng,
            createdAt: now,
            expiresAt: now.add(lifetime),
          ),
        );
      }
    }
  }

  int _latitudeBand(double lat) =>
      (lat * _metersPerDegreeLat / clusterRadiusMeters).floor();

  bool _allPairwiseWithin(List<Session> group, double radius) {
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        final distance = distanceMeters(
          group[i].lat,
          group[i].lng,
          group[j].lat,
          group[j].lng,
        );
        if (distance > radius) return false;
      }
    }
    return true;
  }

  /// Genera ogni sottoinsieme di `items` con esattamente `size` elementi —
  /// chiamato solo sul vicinato di una fascia di latitudine (vedi sopra),
  /// non su tutte le sessioni idonee del server: `items` è già piccolo anche
  /// se il numero totale di sessioni online cresce molto, a patto che non
  /// siano tutte fisicamente ammassate nella stessa manciata di metri.
  Iterable<List<Session>> _combinationsOfSize(
    List<Session> items,
    int size,
  ) sync* {
    if (size == 0) {
      yield [];
      return;
    }
    if (items.length < size) return;

    for (var i = 0; i <= items.length - size; i++) {
      for (final rest in _combinationsOfSize(items.sublist(i + 1), size - 1)) {
        yield [items[i], ...rest];
      }
    }
  }
}
