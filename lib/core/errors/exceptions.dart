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

// --- Verifica del dispositivo ---

/// L'attestazione del dispositivo (App Attest / Play Integrity) non si è
/// potuta produrre sul telefono: simulatore iOS, web, Play Services assenti,
/// configurazione mancante, errore di Apple o Google. Non arriva mai a
/// domain/: la connessione risponde al challenge senza attestazione e
/// decide il server.
class AttestationUnavailableException implements Exception {
  const AttestationUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Il server ha rifiutato la sessione nuova perché manca un'attestazione
/// valida del dispositivo (`error`, code `attestationRequired`, solo con
/// `ATTESTATION_MODE=enforce`).
class DeviceNotVerifiedException implements Exception {
  const DeviceNotVerifiedException([this.message = 'Device not verified']);

  final String message;

  @override
  String toString() => message;
}

// --- Acquisti in-app (paywall) ---

/// Il negozio (App Store / Google Play) non è utilizzabile qui: build senza
/// configurazione, piattaforma senza acquisti in-app, negozio spento o
/// prodotto non trovato.
class StoreUnavailableException implements Exception {
  const StoreUnavailableException([this.message = 'Store unavailable']);

  final String message;

  @override
  String toString() => message;
}

/// La persona ha chiuso la finestra del negozio senza comprare.
class PurchaseCanceledException implements Exception {
  const PurchaseCanceledException([this.message = 'Purchase canceled']);

  final String message;

  @override
  String toString() => message;
}

/// Il negozio ha risposto con un errore (pagamento rifiutato, errore di
/// rete del negozio, acquisto già in corso…).
class StorePurchaseException implements Exception {
  const StorePurchaseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Il server ha verificato la ricevuta col negozio e l'ha rifiutata (422):
/// [code] è il motivo (`invalidReceipt`, `wrongProduct`, `refunded`…).
class PurchaseRejectedException implements Exception {
  const PurchaseRejectedException(this.code);

  final String code;

  @override
  String toString() => 'Purchase rejected: $code';
}

/// La transazione era già stata riscattata e il suo sblocco è finito (409).
class PurchaseAlreadyRedeemedException implements Exception {
  const PurchaseAlreadyRedeemedException();

  @override
  String toString() => 'Purchase already redeemed';
}
