import 'dart:async';
import 'dart:io';

import '../log.dart';
import '../paywall_store.dart';
import '../state/unlock_state_persistence.dart';
import '../state/unlock_state_store.dart';
import 'app_store_server_api.dart';
import 'apple_receipt_verifier.dart';
import 'fake_receipt_verifier.dart';
import 'google_play_api.dart';
import 'google_play_receipt_verifier.dart';
import '../server_environment.dart';
import 'payments_config.dart';
import 'receipt_verifier.dart';
import 'redeemed_transactions.dart';
import 'store_notifications.dart';
import 'unlock_purchase_service.dart';

/// Tutti i pezzi dei pagamenti, montati una volta dalla configurazione
/// (`PaymentsConfig.fromEnvironment`): il servizio di riscatto usato da
/// `POST /paywall/purchase` e i gestori delle notifiche (spenti = `null`).
///
/// - `PAYMENTS_MODE=fake` (o assente): solo la piattaforma `fake`.
/// - `PAYMENTS_MODE=real`: solo `ios`/`android` configurate; quelle senza
///   configurazione rispondono 503, nessuna ricade sul finto.
class Payments {
  Payments._({
    required this.config,
    required this.service,
    this.persistence,
    this.appleNotifications,
    this.googleNotifications,
  });

  factory Payments.fromConfig(
    PaymentsConfig config, {
    PaywallStore? paywallStore,
    GooglePlayApi? googlePlayApi,
    AppStoreServerApi? appStoreServerApi,
    Directory? dataDirectory,
  }) {
    final verifiers = <StorePlatform, ReceiptVerifier>{};
    final productIds = <StorePlatform, String>{};
    final apple = config.apple;
    final google = config.google;

    switch (config.mode) {
      case PaymentsMode.fake:
        verifiers[StorePlatform.fake] = const FakeReceiptVerifier();
        productIds[StorePlatform.fake] = FakeReceiptVerifier.productId;
      case PaymentsMode.real:
        if (apple != null) {
          final credentials = apple.apiCredentials;
          verifiers[StorePlatform.ios] = AppleReceiptVerifier(
            settings: apple,
            api:
                appStoreServerApi ??
                (credentials == null
                    ? null
                    : AppStoreServerApi(
                        credentials: credentials,
                        bundleId: apple.bundleId,
                        environment: apple.environment,
                      )),
          );
          productIds[StorePlatform.ios] = apple.productId;
        }
        if (google != null) {
          verifiers[StorePlatform.android] = GooglePlayReceiptVerifier(
            api:
                googlePlayApi ??
                GooglePlayApiImpl(
                  packageName: google.packageName,
                  serviceAccountJson: google.serviceAccountJson,
                ),
          );
          productIds[StorePlatform.android] = google.productId;
        }
    }

    final store = paywallStore ?? PaywallStore.instance;
    final registry = RedeemedTransactions(hashKey: config.transactionHashKey);
    // Lo stato si salva solo con la chiave fissa: con una casuale per
    // processo gli HMAC salvati non servirebbero a nulla al riavvio dopo.
    final key = config.transactionHashKey;
    final persistence = dataDirectory != null && key != null
        ? UnlockStatePersistence(
            store: UnlockStateStore(directory: dataDirectory, key: key),
            paywall: store,
            registry: registry,
          )
        : null;
    final service = UnlockPurchaseService(
      verifiers: verifiers,
      productIds: productIds,
      registry: registry,
      paywallStore: store,
      persist: persistence?.flush,
    );
    return Payments._(
      config: config,
      service: service,
      persistence: persistence,
      appleNotifications: apple != null && apple.notificationsEnabled
          ? AppleNotificationHandler(settings: apple, service: service)
          : null,
      googleNotifications: google?.rtdnToken != null
          ? GoogleNotificationHandler(settings: google!, service: service)
          : null,
    );
  }

  /// Quella del processo, dalle variabili d'ambiente.
  static final Payments instance = Payments.fromConfig(
    PaymentsConfig.fromEnvironment(),
    dataDirectory: Directory(ServerEnvironment.dataDir(Platform.environment)),
  );

  /// All'avvio: rimette in RAM gli sblocchi e le transazioni salvate e
  /// avvia la pulizia periodica del file. Senza persistenza (chiave HMAC non
  /// fissa) non fa nulla.
  Future<void> start() async {
    final persistence = this.persistence;
    if (persistence == null) return;
    final restored = await persistence.restore();
    Log.info('state.restored', {
      'unlocks': restored.unlocks,
      'transactions': restored.transactions,
    });
    _compactTimer ??= Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(persistence.compact()),
    );
  }

  /// Allo spegnimento: ultima scrittura dello stato e stop del timer.
  Future<void> stop() async {
    _compactTimer?.cancel();
    _compactTimer = null;
    await persistence?.flush();
  }

  Timer? _compactTimer;

  final PaymentsConfig config;
  final UnlockPurchaseService service;

  /// Lo stato degli sblocchi su disco, o `null` (solo RAM).
  final UnlockStatePersistence? persistence;

  /// `null` = `POST /paywall/notifications/apple` risponde 404.
  final AppleNotificationHandler? appleNotifications;

  /// `null` = `POST /paywall/notifications/google` risponde 404.
  final GoogleNotificationHandler? googleNotifications;
}
