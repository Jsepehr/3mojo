// Eccezioni tecniche lanciate dal layer data/ (datasource) quando qualcosa
// va storto (rete, cache, permessi). Il repository le intercetta e le
// traduce nel corrispondente Failure — da domain/ in su non si vedono mai.

class ServerException implements Exception {
  const ServerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CacheException implements Exception {
  const CacheException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocationDisabledException implements Exception {
  const LocationDisabledException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocationPermissionDeniedException implements Exception {
  const LocationPermissionDeniedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Il server ha rifiutato il selfie della presenza (`rejected`, reason
/// `invalidSelfie`).
class SelfieRejectedException implements Exception {
  const SelfieRejectedException([this.message = 'Selfie rejected']);

  final String message;

  @override
  String toString() => message;
}

/// Il selfie non si è potuto preparare per l'invio (ridurre, togliere i
/// metadati) o resta comunque troppo grande per il server: non va mandato.
class SelfiePreparationException implements Exception {
  const SelfiePreparationException([
    this.message = 'Selfie could not be prepared',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Il server non accetta una sessione nuova da questa rete per un po'
/// (`error`, code `rateLimited`).
class RateLimitedException implements Exception {
  const RateLimitedException([this.message = 'Rate limited']);

  final String message;

  @override
  String toString() => message;
}
