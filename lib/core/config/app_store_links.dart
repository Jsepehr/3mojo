import 'dart:io' show Platform;

/// Link pubblici dell'app negli store, aggiunti al testo di "Condividi
/// l'app". **SEGNAPOSTO da compilare alla pubblicazione** (o passare con
/// `--dart-define=IOS_STORE_URL=...` / `ANDROID_STORE_URL=...`): finché
/// iniziano con `TODO_REPLACE_` non si aggiunge nessun link (meglio una frase
/// senza link che un indirizzo finto).
class AppStoreLinks {
  const AppStoreLinks._();

  static const String notConfiguredPrefix = 'TODO_REPLACE_';

  static const String iosUrl = String.fromEnvironment(
    'IOS_STORE_URL',
    defaultValue: 'TODO_REPLACE_https://apps.apple.com/app/idXXXXXXXXXX',
  );

  static const String androidUrl = String.fromEnvironment(
    'ANDROID_STORE_URL',
    defaultValue:
        'TODO_REPLACE_https://play.google.com/store/apps/details?id=com.lemani.app',
  );

  /// Il link dello store della piattaforma corrente, `null` se non
  /// configurato.
  static String? get current {
    final url = Platform.isIOS ? iosUrl : androidUrl;
    return url.startsWith(notConfiguredPrefix) ? null : url;
  }
}
