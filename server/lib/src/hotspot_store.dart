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
/// (vedi `SessionStore.nearbyPeople`, che consulta questo store).
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

  final DateTime Function() _now;
  final List<Hotspot> _hotspots = [];

  /// Gli hotspot ancora attivi — scarta quelli scaduti prima di ritornare.
  List<Hotspot> get active {
    final now = _now();
    _hotspots.removeWhere((h) => now.isAfter(h.expiresAt));
    return List.unmodifiable(_hotspots);
  }

  /// true se esiste un hotspot attivo che copre **entrambe** le posizioni —
  /// non basta che ognuna sia dentro un hotspot qualsiasi, deve essere lo
  /// stesso per entrambe (altrimenti due persone in due zone calde diverse,
  /// dall'altra parte della città, risulterebbero visibili tra loro).
  bool sharesAnyActiveHotspot(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) => active.any(
    (h) =>
        distanceMeters(lat1, lng1, h.centerLat, h.centerLng) <=
            Hotspot.radiusMeters &&
        distanceMeters(lat2, lng2, h.centerLat, h.centerLng) <=
            Hotspot.radiusMeters,
  );

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
  /// 3. Rilevamento: tra le sessioni idonee non già coperte da un hotspot
  ///    (rinnovato o no), cerca ogni gruppo di ≥[minClusterSize] reciprocamente
  ///    entro [clusterRadiusMeters] (tutte le coppie, non solo vicine a un
  ///    centro) e promuove il centroide a nuovo hotspot.
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
        hotspot.centerLat =
            supporters.map((s) => s.lat).reduce((a, b) => a + b) /
            supporters.length;
        hotspot.centerLng =
            supporters.map((s) => s.lng).reduce((a, b) => a + b) /
            supporters.length;
      }
      hotspot.expiresAt = now.add(lifetime);
    }
    _hotspots.removeWhere((h) => now.isAfter(h.expiresAt));

    for (final combo in _combinationsOfSize(eligible, minClusterSize)) {
      if (!_allPairwiseWithin(combo, clusterRadiusMeters)) continue;

      final centerLat =
          combo.map((s) => s.lat).reduce((a, b) => a + b) / combo.length;
      final centerLng =
          combo.map((s) => s.lng).reduce((a, b) => a + b) / combo.length;

      final alreadyCovered = _hotspots.any(
        (h) =>
            distanceMeters(centerLat, centerLng, h.centerLat, h.centerLng) <=
            Hotspot.radiusMeters,
      );
      if (alreadyCovered) continue;

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
  /// alla scala di un singolo server in RAM (decine di sessioni, non
  /// migliaia) è la stessa spesa che `nearbyPeople`/`broadcastNearbyUpdates`
  /// già accettano altrove (O(n²) per broadcast).
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
