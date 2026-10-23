import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma della release: chiavi in android/key.properties (fuori da git, vedi
// key.properties.example e docs/privacy/checklist_prima_del_lancio.md).
// Schema standard di Flutter: storeFile (relativo a android/app/ oppure
// assoluto), storePassword, keyAlias, keyPassword. Debug e profile restano
// firmati con le chiavi di debug, come prima.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")

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

    signingConfigs {
        create("release") {
            // Letti senza controlli qui, perché la configurazione gira per
            // ogni build (anche debug): se mancano, fallisce solo la release
            // (vedi checkReleaseSigning sotto).
            keystoreProperties.getProperty("storeFile")?.let { storeFile = file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            // Mai le chiavi di debug: un APK/AAB firmato così non si può
            // pubblicare né aggiornare con la chiave vera.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Una build release senza key.properties (o con un campo mancante, o con un
// keystore che non esiste) si ferma subito con un messaggio chiaro, invece
// di produrre un APK non firmato o firmato con le chiavi di debug.
val checkReleaseSigning by tasks.registering {
    val propertiesFile = keystorePropertiesFile
    val properties = keystoreProperties
    val keys = releaseSigningKeys
    val appDir = project.projectDir
    doFirst {
        if (!propertiesFile.exists()) {
            throw GradleException(
                "Firma della release mancante: non trovo ${propertiesFile.path}. " +
                    "Copia android/key.properties.example in android/key.properties " +
                    "e compila storeFile, storePassword, keyAlias, keyPassword " +
                    "(passi in docs/privacy/checklist_prima_del_lancio.md). " +
                    "Per provare l'app usa una build debug o profile.",
            )
        }
        val missing = keys.filter { properties.getProperty(it).isNullOrBlank() }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "Firma della release incompleta: in ${propertiesFile.path} " +
                    "mancano ${missing.joinToString()}.",
            )
        }
        val storeFile = appDir.resolve(properties.getProperty("storeFile"))
        if (!storeFile.isFile) {
            throw GradleException(
                "Firma della release: il keystore ${storeFile.path} (storeFile in " +
                    "${propertiesFile.path}, relativo a android/app/) non esiste.",
            )
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(checkReleaseSigning)
}

flutter {
    source = "../.."
}

dependencies {
    // Orientamento EXIF del selfie per il canale `raen/face_detection`
    // (FaceDetectionChannel.kt, che usa `android.media.FaceDetector` del
    // sistema: niente librerie di rilevamento, niente rete). È la stessa
    // versione che image_picker_android porta già nell'APK: dichiararla qui
    // la rende solo visibile al codice dell'app, non aggiunge nulla.
    implementation("androidx.exifinterface:exifinterface:1.4.2")

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
