import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'apple_root_certificates.dart';

/// Come il server accetta i pagamenti (`PAYMENTS_MODE`).
enum PaymentsMode {
  /// Solo ricevute del **negozio simulato** dell'app (build di debug):
  /// nessun pagamento vero, chiunque può fabbricarne una. È il default
  /// quando `PAYMENTS_MODE` manca, per lo sviluppo — e all'avvio il server
  /// lo scrive nel log. **Mai in produzione.**
  fake,

  /// Solo ricevute vere di App Store / Google Play, verificate col negozio.
  /// Una piattaforma senza configurazione completa risponde 503.
  real,
}

enum AppleEnvironment { sandbox, production }

/// Configurazione App Store. La transazione firmata (JWS) di StoreKit 2 si
/// verifica **sul server** con la radice Apple inclusa: bastano bundle id e
/// prodotto. Le credenziali delle API ([apiCredentials]) servono solo per
/// chiedere ad Apple una transazione quando il client non ha mandato il JWS.
class AppleStoreSettings {
  const AppleStoreSettings({
    required this.bundleId,
    required this.productId,
    required this.environment,
    required this.trustedRoots,
    this.apiCredentials,
    this.notificationsEnabled = false,
  });

  final String bundleId;
  final String productId;
  final AppleEnvironment environment;
  final List<Uint8List> trustedRoots;
  final AppleApiCredentials? apiCredentials;
  final bool notificationsEnabled;

  /// Gli ambienti delle transazioni accettate. In produzione anche
  /// `Sandbox`: la revisione dell'app (App Review) compra con account
  /// sandbox su una build di produzione, e rifiutarli farebbe bocciare
  /// l'app. Gli account sandbox li crea solo chi gestisce App Store
  /// Connect.
  Set<String> get acceptedEnvironments => switch (environment) {
    AppleEnvironment.sandbox => {'Sandbox'},
    AppleEnvironment.production => {'Production', 'Sandbox'},
  };
}

class AppleApiCredentials {
  const AppleApiCredentials({
    required this.issuerId,
    required this.keyId,
    required this.privateKeyPem,
  });

  final String issuerId;
  final String keyId;

  /// Il contenuto del file `.p8` (mai loggato).
  final String privateKeyPem;
}

/// Configurazione Google Play: il service account con accesso alla Google
/// Play Developer API (`androidpublisher`) è **obbligatorio**, perché su
/// Android la ricevuta è solo un `purchaseToken` da chiedere a Google.
class GooglePlaySettings {
  const GooglePlaySettings({
    required this.packageName,
    required this.productId,
    required this.serviceAccountJson,
    this.rtdnToken,
  });

  final String packageName;
  final String productId;

  /// Il contenuto del file JSON del service account (mai loggato).
  final String serviceAccountJson;

  /// Segreto delle Real-time Developer Notifications (`?token=` nell'URL
  /// di push di Pub/Sub). `null` = notifiche spente.
  final String? rtdnToken;
}

/// Tutta la configurazione dei pagamenti, letta dalle variabili d'ambiente
/// all'avvio (tabella in `server/README.md`). I problemi (variabili
/// mancanti, file illeggibili) finiscono in [problems] e nel log
/// d'avvio; la piattaforma interessata resta spenta (`null`), **mai** un
/// ripiego sul finto.
class PaymentsConfig {
  const PaymentsConfig({
    required this.mode,
    this.apple,
    this.google,
    this.transactionHashKey,
    this.problems = const [],
  });

  factory PaymentsConfig.fromEnvironment([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final problems = <String>[];

    final rawMode = (env['PAYMENTS_MODE'] ?? '').trim().toLowerCase();
    // Un server con TLS o dietro un proxy fidato è un server pubblico: lì
    // dimenticare PAYMENTS_MODE non deve mai voler dire "chiunque sblocca
    // gratis con una ricevuta fabbricata". Il finto resta possibile solo
    // chiedendolo esplicitamente.
    final looksPublic =
        (env['TLS_CERT_PATH'] ?? '').trim().isNotEmpty ||
        (env['TRUSTED_PROXY'] ?? '').trim().isNotEmpty;
    final PaymentsMode mode;
    if (rawMode.isEmpty && looksPublic) {
      mode = PaymentsMode.real;
      problems.add(
        'PAYMENTS_MODE non impostato su un server con TLS o TRUSTED_PROXY: '
        'modalità reale (mai il finto per dimenticanza). Per i test '
        'impostare esplicitamente PAYMENTS_MODE=fake.',
      );
    } else if (rawMode.isEmpty || rawMode == 'fake') {
      mode = PaymentsMode.fake;
      problems.add(
        rawMode.isEmpty
            ? 'PAYMENTS_MODE non impostato: modalità finta, sblocchi con '
                  'ricevute simulate senza alcun pagamento. In produzione '
                  'impostare PAYMENTS_MODE=real.'
            : 'PAYMENTS_MODE=fake: sblocchi con ricevute simulate senza '
                  'alcun pagamento. Mai in produzione.',
      );
    } else if (rawMode == 'real') {
      mode = PaymentsMode.real;
    } else {
      // Un valore sbagliato non apre mai la porta al finto.
      mode = PaymentsMode.real;
      problems.add(
        'PAYMENTS_MODE="$rawMode" non valido (fake|real): trattato come real.',
      );
    }

    return PaymentsConfig(
      mode: mode,
      apple: mode == PaymentsMode.real ? _apple(env, problems) : null,
      google: mode == PaymentsMode.real ? _google(env, problems) : null,
      transactionHashKey: _hashKey(env, problems),
      problems: problems,
    );
  }

  final PaymentsMode mode;

  /// `null` = iOS spento (modalità finta o configurazione incompleta).
  final AppleStoreSettings? apple;

  /// `null` = Android spento.
  final GooglePlaySettings? google;

  /// Chiave HMAC per gli hash delle transazioni riscattate
  /// (`PAYMENTS_TRANSACTION_HASH_KEY`); `null` = una casuale per processo.
  final Uint8List? transactionHashKey;
  final List<String> problems;

  static AppleStoreSettings? _apple(
    Map<String, String> env,
    List<String> problems,
  ) {
    final bundleId = _value(env, 'APPLE_BUNDLE_ID');
    final productId = _value(env, 'APPLE_PRODUCT_ID');
    final rawEnvironment = _value(env, 'APPLE_ENVIRONMENT')?.toLowerCase();
    final environment = switch (rawEnvironment) {
      'sandbox' => AppleEnvironment.sandbox,
      'production' => AppleEnvironment.production,
      _ => null,
    };
    if (bundleId == null || productId == null || environment == null) {
      problems.add(
        'iOS spento: servono APPLE_BUNDLE_ID, APPLE_PRODUCT_ID e '
        'APPLE_ENVIRONMENT (sandbox|production).',
      );
      return null;
    }

    final List<Uint8List> roots;
    try {
      roots = AppleRootCertificates.trustedRoots(env);
    } catch (e) {
      problems.add('iOS spento: APPLE_ROOT_CA_PATH illeggibile ($e).');
      return null;
    }

    AppleApiCredentials? credentials;
    final issuerId = _value(env, 'APPLE_ISSUER_ID');
    final keyId = _value(env, 'APPLE_KEY_ID');
    final keyPath = _value(env, 'APPLE_PRIVATE_KEY_PATH');
    if (issuerId != null && keyId != null && keyPath != null) {
      try {
        credentials = AppleApiCredentials(
          issuerId: issuerId,
          keyId: keyId,
          privateKeyPem: File(keyPath).readAsStringSync(),
        );
      } catch (_) {
        problems.add(
          'APPLE_PRIVATE_KEY_PATH illeggibile: API App Store spente (si '
          'verificano solo le transazioni firmate mandate dall\'app).',
        );
      }
    } else if (issuerId != null || keyId != null || keyPath != null) {
      problems.add(
        'API App Store spente: servono tutte e tre APPLE_ISSUER_ID, '
        'APPLE_KEY_ID, APPLE_PRIVATE_KEY_PATH.',
      );
    }

    return AppleStoreSettings(
      bundleId: bundleId,
      productId: productId,
      environment: environment,
      trustedRoots: roots,
      apiCredentials: credentials,
      notificationsEnabled:
          _value(env, 'APPLE_NOTIFICATIONS_ENABLED')?.toLowerCase() == 'true',
    );
  }

  static GooglePlaySettings? _google(
    Map<String, String> env,
    List<String> problems,
  ) {
    final packageName = _value(env, 'GOOGLE_PACKAGE_NAME');
    final productId = _value(env, 'GOOGLE_PRODUCT_ID');
    final accountPath = _value(env, 'GOOGLE_SERVICE_ACCOUNT_JSON_PATH');
    if (packageName == null || productId == null || accountPath == null) {
      problems.add(
        'Android spento: servono GOOGLE_PACKAGE_NAME, GOOGLE_PRODUCT_ID e '
        'GOOGLE_SERVICE_ACCOUNT_JSON_PATH.',
      );
      return null;
    }
    final String accountJson;
    try {
      accountJson = File(accountPath).readAsStringSync();
      final decoded = jsonDecode(accountJson);
      if (decoded is! Map || decoded['type'] != 'service_account') {
        throw const FormatException('non è un service account');
      }
    } catch (_) {
      problems.add(
        'Android spento: GOOGLE_SERVICE_ACCOUNT_JSON_PATH illeggibile o non '
        'è il JSON di un service account.',
      );
      return null;
    }

    var rtdnToken = _value(env, 'GOOGLE_RTDN_TOKEN');
    if (rtdnToken != null && rtdnToken.length < 32) {
      problems.add(
        'GOOGLE_RTDN_TOKEN troppo corto (almeno 32 caratteri): notifiche '
        'Google spente.',
      );
      rtdnToken = null;
    }
    return GooglePlaySettings(
      packageName: packageName,
      productId: productId,
      serviceAccountJson: accountJson,
      rtdnToken: rtdnToken,
    );
  }

  static Uint8List? _hashKey(Map<String, String> env, List<String> problems) {
    final raw = _value(env, 'PAYMENTS_TRANSACTION_HASH_KEY');
    if (raw == null) return null;
    try {
      final key = base64.decode(raw);
      if (key.length >= 32) return key;
    } on FormatException {
      // sotto
    }
    problems.add(
      'PAYMENTS_TRANSACTION_HASH_KEY non valida (32 byte in base64): uso una '
      'chiave casuale per processo.',
    );
    return null;
  }

  static String? _value(Map<String, String> env, String name) {
    final value = env[name]?.trim() ?? '';
    return value.isEmpty ? null : value;
  }
}
