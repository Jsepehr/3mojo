import 'package:threemojo_server/src/geo.dart';
import 'package:threemojo_server/src/meeting_chance.dart';

/// Una persona online: la sua posizione più recente, e da quando è "ferma"
/// nello stesso punto — l'ancora di stazionarietà, non la posizione grezza.
/// Se si sposta di più di [SessionStore.stationarityRadiusMeters] rispetto
/// all'ultima posizione nota, l'ancora si aggiorna e il tempo riparte da zero.
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
  });

  final String sessionId;
  double lat;
  double lng;
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

  static const double stationarityRadiusMeters = 30;

  final DateTime Function() _now;
  final Map<String, Session> _sessions = {};

  /// Aggiorna la posizione di `sessionId`. Se si è mossa più di
  /// [stationarityRadiusMeters] dall'ultima posizione nota, l'ancora di
  /// stazionarietà si resetta: è "arrivata altrove", si riparte da zero.
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

    final movedAway =
        distanceMeters(existing.lat, existing.lng, lat, lng) >
        stationarityRadiusMeters;

    existing.lat = lat;
    existing.lng = lng;
    existing.lastSeen = now;
    existing.gender = gender;
    existing.genderPreference = genderPreference;
    existing.selfieBase64 = selfieBase64;
    if (movedAway) existing.arrivedAt = now;
  }

  /// Rimuove `sessionId` dallo store — equivalente del bottone End: chi
  /// esce non deve più comparire nella lista di nessuno.
  void remove(String sessionId) => _sessions.remove(sessionId);

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
}
