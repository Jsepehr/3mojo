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
