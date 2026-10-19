import 'dart:math';

/// Distanza in metri tra due coordinate GPS (formula di Haversine) — la
/// stessa identica formula che userebbe un vero backend, non un'approssimazione.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusMeters = 6371000.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);

  final sinDLat = sin(dLat / 2);
  final sinDLng = sin(dLng / 2);

  final a =
      sinDLat * sinDLat +
      cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sinDLng * sinDLng;
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return earthRadiusMeters * c;
}

double _degToRad(double deg) => deg * pi / 180;

/// `true` solo per coordinate vere: numeri finiti, latitudine in
/// [-90, 90] e longitudine in [-180, 180]. Il JSON in arrivo dal client può
/// contenere valori che `jsonDecode` trasforma in `Infinity` (es. `1e400`) o
/// fuori scala: lasciati passare, finirebbero in `.floor()` dell'indice
/// spaziale, che lancia e bloccava il broadcast per tutti.
bool isValidCoordinate(double lat, double lng) =>
    lat.isFinite &&
    lng.isFinite &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180;
