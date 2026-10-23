import '../paywall_store.dart';
import 'app_store_server_api.dart';
import 'apple_receipt_verifier.dart';
import 'fake_receipt_verifier.dart';
import 'google_play_api.dart';
import 'google_play_receipt_verifier.dart';
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
    this.appleNotifications,
    this.googleNotifications,
  });

  factory Payments.fromConfig(
    PaymentsConfig config, {
    PaywallStore? paywallStore,
    GooglePlayApi? googlePlayApi,
    AppStoreServerApi? appStoreServerApi,
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

    final service = UnlockPurchaseService(
      verifiers: verifiers,
      productIds: productIds,
      registry: RedeemedTransactions(hashKey: config.transactionHashKey),
      paywallStore: paywallStore ?? PaywallStore.instance,
    );
    return Payments._(
      config: config,
      service: service,
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
  );

  final PaymentsConfig config;
  final UnlockPurchaseService service;

  /// `null` = `POST /paywall/notifications/apple` risponde 404.
  final AppleNotificationHandler? appleNotifications;

  /// `null` = `POST /paywall/notifications/google` risponde 404.
  final GoogleNotificationHandler? googleNotifications;
}
