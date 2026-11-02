import 'package:flutter/foundation.dart';

/// Dove si aggiorna l'app: gli indirizzi delle schede negli store, mostrati
/// (e copiabili) quando il server dice che questa versione è troppo vecchia
/// (`AppUpdateRequiredFailure`).
///
/// **SEGNAPOSTO da compilare prima della pubblicazione**: finché l'URL
/// contiene `TODO_REPLACE` l'app non lo mostra (sarebbe un link rotto) e
/// spiega solo che serve aggiornare dallo store. Si compilano qui o con
/// `--dart-define=IOS_STORE_URL=...` / `--dart-define=ANDROID_STORE_URL=...`.
///
/// TODO(release): scheda dell'app su App Store
/// (`https://apps.apple.com/app/id<numero>`) e su Google Play
/// (`https://play.google.com/store/apps/details?id=<package>`).
///
/// L'app non apre link esterni da sola (nessun `url_launcher`, come per
/// l'informativa privacy): il link si copia e si apre dal browser o dallo
/// store.
class AppUpdateConfig {
  const AppUpdateConfig._();

  static const String notConfiguredMarker = 'TODO_REPLACE';

  static const String iosStoreUrl = String.fromEnvironment(
    'IOS_STORE_URL',
    defaultValue: 'https://apps.apple.com/app/idTODO_REPLACE',
  );

  static const String androidStoreUrl = String.fromEnvironment(
    'ANDROID_STORE_URL',
    defaultValue: 'https://play.google.com/store/apps/details?id=TODO_REPLACE',
  );

  /// L'indirizzo dello store per [platform], o `null` se non è configurato
  /// (segnaposto) o la piattaforma non ha uno store (web, desktop).
  static String? storeUrlFor(TargetPlatform platform, {bool isWeb = kIsWeb}) {
    if (isWeb) return null;
    final url = switch (platform) {
      TargetPlatform.iOS => iosStoreUrl,
      TargetPlatform.android => androidStoreUrl,
      _ => '',
    };
    return url.isEmpty || url.contains(notConfiguredMarker) ? null : url;
  }

  /// L'indirizzo per questo dispositivo (vedi [storeUrlFor]).
  static String? get storeUrl => storeUrlFor(defaultTargetPlatform);
}
