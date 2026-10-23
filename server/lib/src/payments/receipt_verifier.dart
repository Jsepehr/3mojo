/// Da quale negozio arriva un acquisto (il campo `platform` di
/// `POST /paywall/purchase`).
enum StorePlatform {
  ios,
  android,

  /// Il negozio **simulato** dell'app nei build di debug: accettato solo con
  /// `PAYMENTS_MODE=fake` (vedi `FakeReceiptVerifier`).
  fake;

  static StorePlatform? fromWire(Object? value) {
    for (final platform in values) {
      if (platform.name == value) return platform;
    }
    return null;
  }
}

/// Ciò che il client **dichiara** di aver comprato: niente di questo è
/// creduto finché un [ReceiptVerifier] non l'ha confermato col negozio.
class PurchaseClaim {
  const PurchaseClaim({
    required this.platform,
    required this.productId,
    required this.receipt,
    required this.transactionId,
  });

  final StorePlatform platform;
  final String productId;

  /// iOS: la transazione firmata (JWS) di StoreKit 2; Android: il
  /// `purchaseToken`; negozio finto: la ricevuta finta firmata.
  final String receipt;

  /// iOS: `transactionId`; Android: `orderId` (può mancare negli acquisti
  /// di prova); negozio finto: l'id della transazione finta.
  final String transactionId;
}

/// Un acquisto **confermato dal negozio**, coi soli dati che servono a
/// decidere se sbloccare.
class VerifiedPurchase {
  const VerifiedPurchase({
    required this.platform,
    required this.transactionKey,
    required this.productId,
    required this.purchasedAt,
    this.alreadyConsumed = false,
    this.storeEnforcesSingleUse = false,
  });

  final StorePlatform platform;

  /// Ciò che identifica la transazione per il negozio (iOS `transactionId`,
  /// Android `purchaseToken`). **Mai salvato così**: il registro ne tiene
  /// solo un HMAC (`RedeemedTransactions`).
  final String transactionKey;

  /// Il prodotto secondo il negozio (non secondo il client).
  final String productId;
  final DateTime purchasedAt;

  /// Il negozio dice che è già stato consumato (Google `consumptionState`
  /// = 1): se non è nel registro, è già stato riscattato altrove/prima.
  final bool alreadyConsumed;

  /// Il negozio stesso impedisce di riusarlo (Google: una volta consumato
  /// non torna "acquistato"). Apple non ha un "consuma" lato server: per
  /// lui vale il limite d'età (`UnlockPurchaseService.maxPurchaseAge`).
  final bool storeEnforcesSingleUse;
}

/// Verifica una ricevuta con il negozio di una piattaforma.
abstract class ReceiptVerifier {
  StorePlatform get platform;

  /// Lancia [ReceiptRejectedException] se il negozio dice che l'acquisto
  /// non vale, [StoreUnavailableException] se non si è potuto chiedere
  /// (si riprova), [StoreNotConfiguredException] se mancano le
  /// credenziali.
  Future<VerifiedPurchase> verify(PurchaseClaim claim);

  /// Dopo che il token di sblocco è stato emesso: chiude l'acquisto dal
  /// lato del negozio (Google: `consume`). Se lancia, lo sblocco viene
  /// annullato e il client riproverà.
  Future<void> finalize(VerifiedPurchase purchase);
}

/// Perché una ricevuta è stata rifiutata — il `code` della risposta 422.
enum ReceiptRejection {
  /// Firma, formato o contenuto non validi; transazione sconosciuta.
  invalidReceipt,

  /// Non è il prodotto dello sblocco configurato.
  wrongProduct,

  /// Di un'altra app (bundle id / package name diversi).
  wrongApp,

  /// Dell'ambiente sbagliato (es. sandbox con `APPLE_ENVIRONMENT=sandbox`
  /// ma transazione di produzione).
  wrongEnvironment,

  /// Il negozio non lo dà per pagato (annullato, in attesa).
  notPurchased,

  /// Rimborsato o revocato.
  refunded,

  /// Troppo vecchio per essere riscattato ora (vedi
  /// `UnlockPurchaseService.maxPurchaseAge`).
  tooOld,

  /// La transazione dichiarata dal client non è quella firmata dal negozio.
  transactionMismatch,
}

class ReceiptRejectedException implements Exception {
  const ReceiptRejectedException(this.reason, [this.detail = '']);

  final ReceiptRejection reason;

  /// Solo per il log del server, mai nella risposta.
  final String detail;

  @override
  String toString() => 'ReceiptRejectedException(${reason.name}): $detail';
}

/// Il negozio non ha risposto o ha risposto con un errore temporaneo: il
/// client tiene l'acquisto e riprova (502).
class StoreUnavailableException implements Exception {
  const StoreUnavailableException(this.detail);

  final String detail;

  @override
  String toString() => 'StoreUnavailableException: $detail';
}

/// Il server non è configurato per questa piattaforma (credenziali mancanti
/// o rifiutate dal negozio): 503, nessun token.
class StoreNotConfiguredException implements Exception {
  const StoreNotConfiguredException(this.detail);

  final String detail;

  @override
  String toString() => 'StoreNotConfiguredException: $detail';
}
