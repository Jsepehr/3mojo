import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licenze che la `LicensePage` di Flutter non trova da sola: lei elenca
/// solo i pacchetti Dart (e il motore), non i font inclusi a mano né le
/// librerie native aggiunte fuori da pub.
///
/// - **Manrope** (font dell'app, `assets/fonts/manrope/`): SIL OFL 1.1.
/// - **Android**: le librerie native che finiscono nell'APK senza un
///   pacchetto Dart che ne porti la licenza — Play Integrity (aggiunta a
///   mano in `android/app/build.gradle.kts` per `AttestationChannel.kt`) e
///   le dipendenze Gradle dirette dei plugin (Google Play services, Google
///   Play Billing Library, Tink, AndroidX, Kotlin). Il volto lo rileva
///   `android.media.FaceDetector` del sistema operativo
///   (`FaceDetectionChannel.kt`): nessuna libreria da elencare. Registrate
///   **solo su Android**: su iOS il volto lo rileva Apple Vision (framework
///   di sistema) e i plugin arrivano via Swift Package Manager senza
///   pacchetti esterni — non c'è nulla da aggiungere.
///
/// I testi sono letti dagli asset solo quando qualcuno apre la pagina delle
/// licenze (`LicenseRegistry` chiama il collector in modo pigro). Sono in
/// inglese come tutte le altre licenze della pagina: testi legali, non
/// interfaccia (niente ARB).
void registerAppLicenses({AssetBundle? bundle, TargetPlatform? platform}) {
  final assets = bundle ?? rootBundle;
  final target = platform ?? defaultTargetPlatform;
  LicenseRegistry.addLicense(() => appLicenses(assets, target));
}

/// Le voci di [registerAppLicenses], separate per poterle provare senza
/// toccare il registro globale.
@visibleForTesting
Stream<LicenseEntry> appLicenses(
  AssetBundle bundle,
  TargetPlatform platform,
) async* {
  yield LicenseEntryWithLineBreaks(const [
    'Manrope',
  ], await bundle.loadString(manropeLicenseAsset));

  if (platform != TargetPlatform.android) return;

  yield const LicenseEntryWithLineBreaks([
    'Google Play services',
  ], _playServicesTerms);
  yield const LicenseEntryWithLineBreaks([
    'Google Play Billing Library',
  ], _playBillingTerms);
  yield const LicenseEntryWithLineBreaks([
    'Google Play Integrity',
  ], _playIntegrityTerms);

  final apache = await bundle.loadString(apacheLicenseAsset);
  for (final library in _apacheLibraries) {
    yield LicenseEntryWithLineBreaks([
      library.name,
    ], '${library.notice}\n\n$apache');
  }
}

@visibleForTesting
const manropeLicenseAsset = 'assets/fonts/manrope/OFL.txt';

@visibleForTesting
const apacheLicenseAsset = 'assets/licenses/apache-2.0.txt';

/// Le librerie Google qui sotto non sono open source: si usano alle
/// condizioni dei termini di Google, che non sono un testo da copiare qui ma
/// pagine che Google aggiorna — le voci rimandano a quelle (gli stessi
/// indirizzi dei POM Maven delle librerie).
const _playServicesTerms =
    'com.google.android.gms:play-services-location (location for the '
    '"Nearby" list, via the geolocator plugin) and the Google Play services '
    'components it pulls in (play-services-base, play-services-basement, '
    'play-services-tasks).\n\n'
    'Copyright Google LLC. Used under the Android Software Development Kit '
    'License Agreement: https://developer.android.com/studio/terms';

const _playBillingTerms =
    'com.android.billingclient:billing (in-app purchase of the unlock, via '
    'the in_app_purchase plugin).\n\n'
    'Copyright Google LLC. Used under the Android Software Development Kit '
    'License Agreement: https://developer.android.com/studio/terms';

const _playIntegrityTerms =
    'com.google.android.play:integrity and com.google.android.play:'
    'core-common (device check, only when the server asks for it).\n\n'
    'Copyright Google LLC. Used under the Play Integrity API Terms of '
    'Service: https://developer.android.com/google/play/integrity/overview#tos '
    'and the Play Core Software Development Kit Terms of Service: '
    'https://developer.android.com/guide/playcore/license';

/// Librerie Apache 2.0 dirette dei plugin Android (dai loro
/// `android/build.gradle`): nome e riga di copyright; il testo della
/// licenza è lo stesso per tutte.
const _apacheLibraries = <({String name, String notice})>[
  (
    name: 'AndroidX',
    notice:
        'androidx.core, androidx.activity, androidx.annotation, '
        'androidx.exifinterface, androidx.datastore, androidx.preference.\n'
        'Copyright The Android Open Source Project.',
  ),
  (
    name: 'Tink',
    notice:
        'com.google.crypto.tink:tink-android (encryption of the on-device '
        'storage, via flutter_secure_storage).\n'
        'Copyright Google LLC.',
  ),
  (
    name: 'Kotlin',
    notice:
        'org.jetbrains.kotlin:kotlin-stdlib, '
        'org.jetbrains.kotlinx:kotlinx-coroutines-android.\n'
        'Copyright JetBrains s.r.o. and Kotlin Programming Language '
        'contributors.',
  ),
];
