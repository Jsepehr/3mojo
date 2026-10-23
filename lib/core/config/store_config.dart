import 'package:flutter/foundation.dart';

/// Come si paga lo sblocco in questo build.
enum StoreMode {
  /// Negozio **simulato** (`StoreBillingDataSourceFakeImpl`): nessun
  /// addebito. Solo nei build di debug.
  fake,

  /// App Store / Google Play veri (`StoreBillingDataSourceImpl`).
  real,

  /// Il pagamento non può partire: il bottone dice "Non disponibile". È
  /// ciò che succede in un build di release senza configurazione — **mai**
  /// uno sblocco gratuito.
  unavailable,
}

/// L'unico posto con la configurazione degli acquisti in-app dello
/// sblocco (2 ore, prodotto **consumabile**). Passare al pagamento reale
/// richiede solo di compilare qui gli ID (o passarli con `--dart-define`) e
/// accendere [realPaymentsEnabled] — nessun altro codice cambia.
///
/// ```
/// flutter build ipa --release \
///   --dart-define=REAL_PAYMENTS=true \
///   --dart-define=IOS_UNLOCK_PRODUCT_ID=<id del prodotto in App Store Connect> \
///   --dart-define=API_BASE_URL=https://<server>
/// flutter build appbundle --release \
///   --dart-define=REAL_PAYMENTS=true \
///   --dart-define=ANDROID_UNLOCK_PRODUCT_ID=<id del prodotto in Play Console> \
///   --dart-define=API_BASE_URL=https://<server>
/// ```
///
/// Gli stessi ID vanno sul server (`APPLE_PRODUCT_ID`, `GOOGLE_PRODUCT_ID`):
/// il server rifiuta qualsiasi altro prodotto. Passi completi in
/// `guida_per_sviluppatori.md` ("Pagamenti").
class StoreConfig {
  const StoreConfig._();

  /// Pagamenti veri accesi (`--dart-define=REAL_PAYMENTS=true`). Spenti
  /// (il default): negozio simulato in debug, "non disponibile" in release.
  static const bool realPaymentsEnabled = bool.fromEnvironment('REAL_PAYMENTS');

  /// Segnaposto: un ID che inizia così **non** è configurato.
  static const String notConfiguredPrefix = 'TODO_REPLACE_';

  /// ID del prodotto consumabile in **App Store Connect**.
  /// TODO(pagamenti): sostituire quando il prodotto esiste (o usare
  /// `--dart-define=IOS_UNLOCK_PRODUCT_ID=...`).
  static const String iosUnlockProductId = String.fromEnvironment(
    'IOS_UNLOCK_PRODUCT_ID',
    defaultValue: 'TODO_REPLACE_ios_unlock_2h',
  );

  /// ID del prodotto a pagamento singolo in **Google Play Console**.
  /// TODO(pagamenti): sostituire quando il prodotto esiste (o usare
  /// `--dart-define=ANDROID_UNLOCK_PRODUCT_ID=...`).
  static const String androidUnlockProductId = String.fromEnvironment(
    'ANDROID_UNLOCK_PRODUCT_ID',
    defaultValue: 'TODO_REPLACE_android_unlock_2h',
  );

  /// Il prodotto del negozio simulato: lo stesso che il server accetta con
  /// `PAYMENTS_MODE=fake` (`FakeReceiptVerifier.productId`).
  static const String fakeUnlockProductId = 'raen.fake.unlock_2h';

  /// Chiave (pubblica, **non** un segreto) con cui il negozio simulato firma
  /// le ricevute finte: la stessa di `FakeReceiptVerifier.signingKey` sul
  /// server. Serve solo a riconoscerle e a scartare quelle rovinate.
  static const String fakeStoreSigningKey =
      'raen-fake-store-not-a-real-payment';

  static bool isConfigured(String productId) =>
      productId.isNotEmpty && !productId.startsWith(notConfiguredPrefix);

  /// L'ID del prodotto su questa piattaforma, o `null` se gli acquisti
  /// in-app non esistono qui (web, desktop) o l'ID è ancora un segnaposto.
  static String? unlockProductIdFor(
    TargetPlatform platform, {
    bool isWeb = kIsWeb,
  }) {
    if (isWeb) return null;
    final id = switch (platform) {
      TargetPlatform.iOS => iosUnlockProductId,
      TargetPlatform.android => androidUnlockProductId,
      _ => '',
    };
    return isConfigured(id) ? id : null;
  }

  /// La regola di scelta del negozio, separata per poterla provare:
  /// - pagamenti veri accesi e prodotto configurato → [StoreMode.real]
  ///   (anche in debug: per provare la sandbox);
  /// - accesi ma senza prodotto → [StoreMode.unavailable] (configurazione a
  ///   metà, mai ripiego sul finto);
  /// - spenti → [StoreMode.fake] solo in debug, altrimenti
  ///   [StoreMode.unavailable].
  static StoreMode resolveMode({
    required bool debugBuild,
    required bool realPaymentsEnabled,
    required String? productId,
  }) {
    if (realPaymentsEnabled) {
      return productId != null ? StoreMode.real : StoreMode.unavailable;
    }
    return debugBuild ? StoreMode.fake : StoreMode.unavailable;
  }

  /// La modalità di questo build.
  static StoreMode get mode => resolveMode(
    debugBuild: kDebugMode,
    realPaymentsEnabled: realPaymentsEnabled,
    productId: unlockProductIdFor(defaultTargetPlatform),
  );
}
