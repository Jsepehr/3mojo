# Macchine di sviluppo

`android/gradle.properties` (`org.gradle.java.home`) e `.vscode/settings.json`
(`dart.flutterSdkPath`, `dart.sdkPath`, i due `java.*.home`) contengono
percorsi assoluti — JDK e SDK Flutter installati sul PC in uso. Cambiando
macchina questi percorsi non esistono più e la build Android fallisce
(`Java home supplied is invalid`) o l'estensione Dart non trova l'SDK.

Quando succede: aggiorna i due file con i percorsi della tabella qui sotto
per la macchina in uso, oppure scoprili di nuovo (`where flutter`, cerca
`Android Studio` e la cartella `.jdks`) e aggiungi una riga nuova.

| Macchina | JDK (`org.gradle.java.home` / `java.*.home`) | Flutter SDK (`dart.flutterSdkPath`) |
|---|---|---|
| PC con utente `sepehrbaradaran`, dati su `C:` | `C:\Users\sepehrbaradaran\.jdks\azul-17.0.16` | `C:\Users\sepehrbaradaran\flutter_new\flutter_windows_3.38.3-stable\flutter` |
| PC con Android Studio/Flutter su `D:\Programs` | `D:\Programs\Android Studio\jbr` | `D:\Programs\flutter_windows_3.41.7-stable\flutter` |

`dart.sdkPath` è sempre `<dart.flutterSdkPath>\bin\cache\dart-sdk`. Il nome
in `java.configuration.runtimes` è `JavaSE-17` per l'Azul 17, `JavaSE-21`
per il JBR di Android Studio (segue la versione Java effettiva del JDK).
