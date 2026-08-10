// Eccezioni tecniche lanciate dal layer data/ (datasource) quando qualcosa
// va storto (rete, cache, permessi). Il repository le intercetta e le
// traduce nel corrispondente Failure — da domain/ in su non si vedono mai.

class ServerException implements Exception {
  const ServerException(this.message);

  final String message;
}

class CacheException implements Exception {
  const CacheException(this.message);

  final String message;
}

class LocationDisabledException implements Exception {
  const LocationDisabledException(this.message);

  final String message;
}

class LocationPermissionDeniedException implements Exception {
  const LocationPermissionDeniedException(this.message);

  final String message;
}
