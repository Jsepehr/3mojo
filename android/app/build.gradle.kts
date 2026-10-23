plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.threemojo.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.threemojo.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Rilevamento volto sul dispositivo per il canale `raen/face_detection`
    // (FaceDetectionChannel.kt): stessa versione che usava il plugin
    // google_mlkit_face_detection, modello incluso nell'APK.
    //
    // Privacy: le immagini non escono dal telefono, ma ML Kit invia a Google
    // (via com.google.android.datatransport, HTTPS) telemetria di diagnostica
    // e uso: modello/OS del dispositivo, nome pacchetto e versione app, un
    // identificativo per installazione, latenza, configurazione dell'API,
    // dimensione di input/output, codici d'errore. Google non documenta un
    // modo supportato per disattivarla (togliere a mano datatransport non è
    // supportato e può rompere il rilevamento): va dichiarata nel Data Safety
    // di Play — vedi https://developers.google.com/ml-kit/android-data-disclosure
    implementation("com.google.mlkit:face-detection:16.1.7")

    // Verifica del dispositivo per il canale `raen/attestation`
    // (AttestationChannel.kt): Play Integrity API, Standard request. Usata
    // solo se il server la chiede (`ATTESTATION_MODE=log|enforce`).
    //
    // Privacy: il token va dal Play Store ai server di Google e poi al nostro
    // server, che lo fa decodificare a Google e tiene solo l'esito (niente
    // id del dispositivo né dell'account). Google raccoglie e tratta dati del
    // dispositivo per calcolare il verdetto: va dichiarato nel Data Safety di
    // Play — vedi https://developer.android.com/google/play/integrity/overview
    // e la guida per sviluppatori ("Per attivare la verifica del dispositivo").
    implementation("com.google.android.play:integrity:1.6.0")
}
