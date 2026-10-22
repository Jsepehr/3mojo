import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licenze che la `LicensePage` di Flutter non trova da sola: lei elenca
/// solo i pacchetti Dart (e il motore), non i font inclusi a mano né le
/// librerie native aggiunte fuori da pub.
///
/// - **Manrope** (font dell'app, `assets/fonts/manrope/`): SIL OFL 1.1.
/// - **Android**: le librerie native che finiscono nell'APK senza un
///   pacchetto Dart che ne porti la licenza — ML Kit (aggiunto a mano in
///   `android/app/build.gradle.kts` per `FaceDetectionChannel.kt`) e le
///   dipendenze Gradle dirette dei plugin (Google Play services, Tink,
///   AndroidX, Kotlin). Registrate **solo su Android**: su iOS il volto lo
///   rileva Apple Vision (framework di sistema) e i plugin arrivano via
///   Swift Package Manager senza pacchetti esterni — non c'è nulla da
///   aggiungere.
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

  yield const LicenseEntryWithLineBreaks(['Google ML Kit'], _mlKitTerms);
  yield const LicenseEntryWithLineBreaks([
    'Google Play services',
  ], _playServicesTerms);

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

/// ML Kit non è open source: si usa alle condizioni dei termini di Google,
/// che non sono un testo da copiare qui ma una pagina che Google aggiorna —
/// la voce rimanda a quella.
const _mlKitTerms =
    'com.google.mlkit:face-detection 16.1.7 — on-device face detection, '
    'used only to check that a selfie contains a face before going online. '
    'Images never leave the device.\n\n'
    'Copyright Google LLC. Used under the ML Kit Terms of Service: '
    'https://developers.google.com/ml-kit/terms\n\n'
    'ML Kit sends Google diagnostic and usage data about the API (not the '
    'images): https://developers.google.com/ml-kit/android-data-disclosure';

const _playServicesTerms =
    'com.google.android.gms:play-services-location (location for the '
    '"Nearby" list, via the geolocator plugin) and the Google Play services '
    'components pulled in by ML Kit.\n\n'
    'Copyright Google LLC. Used under the Android Software Development Kit '
    'License Agreement: https://developer.android.com/studio/terms';

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
