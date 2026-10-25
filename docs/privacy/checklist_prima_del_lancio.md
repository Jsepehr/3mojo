# Raen: checklist prima del lancio

> **Bozza tecnica, non consulenza legale.** Elenco operativo di ciò che resta da fare prima di pubblicare su App Store e Google Play, ricavato dal codice al commit `4f7cae1` (più la rimozione di ML Kit, la firma della release, l'informativa in app, l'avviso in evidenza sulla posizione, il ritiro del consenso da online e il consenso versionato) e da [dpia.md](dpia.md). Spuntare ogni voce con data e responsabile. Le voci **[B]** sono bloccanti.

## 1. Legale e organizzazione

- [ ] **[B]** Compilare i dati del titolare in [registro_trattamenti.md](registro_trattamenti.md) e [informativa_bozza.md](informativa_bozza.md).
- [ ] **[B]** Far rivedere e approvare la [DPIA](dpia.md) dal consulente legale o dal DPO; decidere sui rischi residui (§6) e, se restano alti, valutare la consultazione preventiva del Garante (art. 36).
- [ ] Decidere sul **DPO** (art. 37) e, se il titolare non è stabilito nell'UE, sul **rappresentante UE** (art. 27).
- [ ] **[B]** Scegliere l'**hosting** (raccomandato nell'UE), firmare il **contratto art. 28**, controllare i sub-responsabili e dove finiscono i backup (la cartella dei record di moderazione non deve stare nello stesso backup della `MODERATION_KEY`).
- [ ] Qualificare il ruolo di **Apple e Google** per servizio (distribuzione, pagamenti, App Attest, Play Integrity, eventuale diagnostica della Play Billing Library) e i **trasferimenti extra UE** (DPF o clausole tipo).
- [ ] Valutare l'art. 5(3) ePrivacy / art. 122 Codice privacy per l'attestazione del dispositivo e per l'eventuale diagnostica della Play Billing Library (la telemetria ML Kit non c'è più).
- [ ] Valutare gli obblighi del **DSA** (punto di contatto, segnalazioni, motivazione delle restrizioni come la chiusura automatica, reclami) e le esenzioni per micro e piccole imprese.
- [ ] **[B]** Pubblicare l'**informativa privacy** a un URL stabile (IT ed EN, più le altre lingue dell'app se possibile).
- [ ] **[B]** Rivedere i **termini d'uso** in app (`CmpTermsOfUse`) con il consulente. Se cambiano nella sostanza, alzare `Profile.currentTermsVersion`.
- [ ] **[B]** Scrivere la **procedura di moderazione**: chi revisiona i record (`/admin/reports`), entro quanto (Apple si aspetta un intervento entro 24 ore), cosa fare per "sembra minorenne" e per segnalazioni di reati, quando cancellare un record, come rispondere a un ricorso.
- [ ] Scrivere la **procedura per i diritti degli interessati** senza account (accesso, cancellazione e opposizione per i record di moderazione; risposta tipo "non abbiamo dati della sessione chiusa").
- [ ] Scrivere la **procedura per le violazioni di dati** (artt. 33-34: notifica entro 72 ore).
- [ ] Decidere la **conservazione dei log** del reverse proxy e del provider (raccomandati ≤ 7 giorni, senza query string) e delle email del contatto di sicurezza.
- [ ] Decidere sulla **verifica dell'età** (oggi solo autodichiarazione 18+).
- [ ] Istruzioni scritte (art. 29) per chi ha accesso ad `ADMIN_TOKEN` e `MODERATION_KEY`.

## 2. App: modifiche prima della release (codice non toccato in questa revisione)

- [ ] **[B]** **Email di sicurezza** vera e presidiata in `lib/core/config/safety_contact.dart:12` (oggi `safety@raen.example`, che non riceve posta).
- [x] **[B]** **Informativa privacy in app**: `UiPrivacyPolicy` (testi `privacy_*` negli ARB di tutte le lingue), dal menu laterale, da "Informazioni", dal profilo (anche nell'onboarding, accanto a consenso e termini) e dai termini d'uso. Resta da compilare `lib/core/config/privacy_policy_info.dart` (segnaposto `TODO(privacy)`: titolare, email, hosting, garanzie, data) e da pubblicare l'URL (§1).
- [x] **[B, Android]** **Informativa in evidenza** sulla posizione anche in background, **prima** della richiesta del permesso: `UiLocationDisclosure` al tap su Start, finché il permesso non è concesso; anche su iOS, con il testo "solo con l'app aperta" (testi in [store_privacy.md](store_privacy.md) §C).
- [x] Ritiro del consenso immediato: una modifica del profilo da online che cambia genere, chi cerchi, "mostra il mio genere" o fa perdere il consenso chiude prima la sessione, con conferma (`UpdateProfileUseCase`, DPIA D4 e §6.9). Lingue e intento predefinito valgono dal prossimo Start.
- [x] Salvare la **versione del consenso** al dato sensibile nel profilo, come `acceptedTermsVersion` (DPIA D5): `Profile.acceptedSensitiveConsentVersion`, attuale `Profile.currentSensitiveConsentVersion = 1`. Se il testo del consenso cambia nella sostanza, alzarla: va riconfermato al salvataggio e allo Start.
- [x] `android.media.FaceDetector` al posto di ML Kit: il controllo del volto su Android non contatta più Google (DPIA §6.7). Resta da provare su telefoni veri (§6).
- [ ] Verificare cosa invia a Google la **Play Billing Library** (trasporto di log `datatransport` nell'APK) e allineare Data safety e informativa (DPIA §6.7).
- [x] Commenti sulle "distanze" in `MainActivity.kt` e `AppDelegate.swift`; pulizia di `Hotspot.memberSessionIds` a fine sessione (DPIA D8, D9).
- [x] **Firma di release configurata**: `android/app/build.gradle.kts` firma la release con le chiavi di `android/key.properties` e, se il file manca o è incompleto, la build release **si ferma** (nessun ripiego sulle chiavi di debug). Debug e profile restano con le chiavi di debug.
- [ ] **[B, Android]** Creare la **chiave di upload** e conservarla come descritto in §2.1.
- [ ] **[B]** **JDK**: `android/gradle.properties` fissa `org.gradle.java.home` a `C:\Users\sepehrbaradaran\.jdks\azul-17.0.16` (una macchina Windows). Sulla macchina o CI che fa la build di release va adattato (percorsi in `macchine_sviluppo.md`), senza committare un percorso di un'altra macchina.
- [ ] Build di release con: `--dart-define=API_BASE_URL=https://<server>` (obbligatorio, solo https), `REAL_PAYMENTS=true`, `IOS_UNLOCK_PRODUCT_ID`/`ANDROID_UNLOCK_PRODUCT_ID` (oggi `TODO_REPLACE_…` in `lib/core/config/store_config.dart`), `GOOGLE_CLOUD_PROJECT_NUMBER` (per Play Integrity).
- [ ] iOS: capability **App Attest** sull'App ID; entitlement `production` già in `ios/Runner/Runner.entitlements`.
- [x] **Modalità demo dichiarata** per la revisione con un solo telefono (Apple 2.1), senza profili finti nel servizio vero: link "Come funziona? Prova la demo" sotto Start e nel profilo da compilare, voce "Prova la demo" nel menu (solo da offline). Tutta sul telefono (`DemoScope`, `lib/demo_scope.dart`): datasource finti anche in release, nessun messaggio al server né WebSocket, nessuna posizione, fotocamera, permesso o negozio vero; avatar illustrati generati sul telefono; banner fisso "Demo — persone dimostrative, non reali" e badge "Demo" su ogni persona; all'uscita si azzera tutto (passi di End). Test in `test/features/demo/demo_mode_test.dart`.
- [ ] Provare la demo su un telefono vero **in release** e in modalità aereo (deve funzionare uguale): ingresso dalla home, dal menu e dal profilo da compilare; richiesta → sì → chat; richiesta in arrivo dopo ~15 s; Blocca/Segnala; sblocco gratuito col timer; Esci dalla demo ed End riportano alla home vera; VoiceOver/TalkBack leggono il banner e "Persona dimostrativa".

### 2.1 Firma della release Android

Con **Play App Signing** (consigliato, e obbligatorio per gli AAB) le chiavi sono due: la **chiave dell'app**, che firma ciò che arriva sui telefoni, la genera e la custodisce Google; la **chiave di upload**, nostra, firma solo gli AAB che carichiamo. Se la chiave di upload si perde o viene rubata, Google la può sostituire (Play Console → Integrità dell'app → Richiedi reimpostazione della chiave di upload); la chiave dell'app no. Per questo conviene lasciare la chiave dell'app a Google e non generarla in casa.

- [ ] **Creare la chiave di upload** su una macchina fidata, fuori dal repository (JDK 17; `keytool` sta in `$JAVA_HOME/bin`):
  ```sh
  keytool -genkeypair -v -keystore ~/raen-upload-keystore.jks \
    -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload
  ```
  `keytool` chiede la password del keystore e i dati del certificato (nome, organizzazione: non vanno a nessuno salvo che dentro il certificato). Con PKCS12 la password della chiave è la stessa del keystore. Validità di 10000 giorni (circa 27 anni): Play chiede che il certificato scada dopo il 22 ottobre 2033.
- [ ] **Configurare la build**: copiare `android/key.properties.example` in `android/key.properties` e compilare `storeFile` (percorso assoluto del `.jks`, o relativo a `android/app/`), `storePassword`, `keyAlias=upload`, `keyPassword`. `key.properties`, `*.jks` e `*.keystore` sono esclusi da git (`.gitignore` e `android/.gitignore`): controllare con `git status` che non compaiano mai.
- [ ] **Provare**: `flutter build appbundle --release` (con le `--dart-define` del §2). Senza `key.properties` la build deve fermarsi con il messaggio "Firma della release mancante". Il certificato usato si vede con `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab`.
- [ ] **Attivare Play App Signing** al primo caricamento in Play Console (Configura → Integrità dell'app), lasciando generare a Google la chiave dell'app. Annotare le impronte SHA-256 di entrambe le chiavi (servono, per esempio, per eventuali App Links).
- [ ] **Conservare** il keystore e le password in **due posti separati** e cifrati (per esempio il gestore di password aziendale per le password e un backup cifrato offline per il `.jks`), con l'elenco delle persone che vi hanno accesso. Mai nel repository, in chat, in email o nei log della CI. In una CI: keystore e password come segreti cifrati, scritti su disco solo durante la build.
- [ ] Decidere chi può chiedere a Google la **reimpostazione della chiave di upload** (proprietario dell'account sviluppatore) e annotarlo nelle procedure.

## 3. Traduzioni

- [ ] **[B]** Revisione **da madrelingua** di `lib/l10n/app_de.arb`, `app_es.arb`, `app_fr.arb`, `app_ar.arb` (e rilettura di `app_it.arb`), con precedenza a: consenso al dato sensibile, termini d'uso, testi di sicurezza e moderazione, notifica del foreground service, errori di permesso, dialogo d'acquisto (prezzo, durata, "non si rinnova").
- [ ] Stessa revisione per `ios/Runner/*.lproj/InfoPlist.strings` (permessi di fotocamera e posizione).
- [ ] Arabo: controllare l'impaginazione da destra a sinistra delle pagine con testo lungo (termini, sicurezza, profilo).
- [ ] Informativa e note di revisione nelle lingue in cui l'app esce.

## 4. Server: configurazione di produzione

Riferimento: tabella delle variabili in `server/README.md`.

- [ ] **[B]** **TLS**: `TLS_CERT_PATH` + `TLS_KEY_PATH`, oppure un reverse proxy che termina TLS e non è raggiungibile in chiaro dall'esterno.
- [ ] **[B]** **`TRUSTED_PROXY`** con gli IP del proxy, se c'è un proxy. Senza, tutti i client sembrano lo stesso IP: limiti per IP e soglia dei 2 IP non funzionano, e il cooldown colpirebbe tutti. Il proxy deve mandare `X-Forwarded-For` e `X-Forwarded-Proto: https`.
- [ ] **[B]** **`MODERATION_KEY`** (32 byte in base64, `openssl rand -base64 32`), fuori dal repository e dai backup dei record. Senza, i record **non** vengono salvati (lo dice il log all'avvio).
- [ ] **`MODERATION_DIR`** su un disco non condiviso, permessi `700`, incluso nei piani di cancellazione (i file oltre 30 giorni li cancella il server, ma un backup del disco no).
- [ ] **[B]** **`ADMIN_TOKEN`** (≥ 32 caratteri, `openssl rand -hex 32`) per gli endpoint `/admin/reports`. **Non** impostare `ADMIN_ALLOW_INSECURE_HTTP`.
- [ ] **[B]** **`PAYMENTS_MODE=real`** con `APPLE_BUNDLE_ID`, `APPLE_PRODUCT_ID`, `APPLE_ENVIRONMENT=production`, `GOOGLE_PACKAGE_NAME`, `GOOGLE_PRODUCT_ID`, `GOOGLE_SERVICE_ACCOUNT_JSON_PATH`. Mai `fake` in produzione (con TLS o proxy il default è già `real`).
- [ ] Notifiche di rimborso: `APPLE_NOTIFICATIONS_ENABLED=true`, `GOOGLE_RTDN_TOKEN`, URL configurati negli store.
- [ ] Limite noto: registro delle transazioni in RAM (dopo un riavvio una transazione Apple con meno di 7 giorni si può riscattare di nuovo). Valutare la persistenza (solo HMAC più data, 8 giorni) con `PAYMENTS_TRANSACTION_HASH_KEY` fissa.
- [ ] **`ATTESTATION_MODE=log`** al lancio con `APPLE_TEAM_ID`, `APPLE_APP_ATTEST_ENVIRONMENT=production`, `PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_PATH` (o quello dei pagamenti); dopo 1-2 settimane di metriche, **`enforce`**. **Non** impostare `ATTESTATION_ALLOW_FAKE`.
- [ ] **Non** impostare `DEBUG_ENDPOINTS_TOKEN` in produzione.
- [ ] `MAX_NEW_SESSIONS_PER_IP` al default (20) e `MODERATION_COOLDOWN_MINUTES` al default (30) o più basso, se gli IP condivisi creano problemi.
- [ ] Log del reverse proxy: spenti o ridotti, senza corpo delle richieste, con conservazione breve. Niente core dump, swap cifrato, accesso SSH ristretto, aggiornamenti automatici.
- [ ] Monitoraggio: il server deve ripartire da solo; un riavvio cancella tutte le sessioni (comportamento voluto) ma non i record.

## 5. Store

**Apple**
- [ ] **[B]** App Privacy compilata come in [store_privacy.md](store_privacy.md) §A ("Linked to you", più Purchase History).
- [ ] Privacy Report dell'archivio Xcode controllato (manifest dei plugin, required reason API).
- [ ] **[B]** URL dell'informativa privacy (e del supporto) in App Store Connect.
- [ ] Classificazione d'età **18+**.
- [ ] Prodotto in-app **consumabile** creato e inviato **insieme** alla build; accordo "App a pagamento" attivo.
- [ ] Note di revisione (§D): spiegare la **modalità demo dichiarata** (come aprirla, perché esiste, che non mostra mai persone demo agli utenti reali e non contatta il server), più, se possibile, video del flusso reale con due telefoni o disponibilità a una prova dal vivo; contatto per la revisione.
- [ ] Screenshot dello store: se presi dalla demo, banner e badge "Demo" visibili; mai far passare le persone dimostrative per utenti reali.

**Google Play**
- [ ] **[B]** Data safety come in [store_privacy.md](store_privacy.md) §B (Play Integrity ed eventuale diagnostica della Play Billing Library; **niente più telemetria ML Kit**: se era già stata dichiarata, toglierla).
- [ ] **[B]** Dichiarazione dei **servizi in primo piano** (tipo "Posizione") con video (§C).
- [ ] Verificare sull'AAB finale (Esplora app bundle) l'**assenza** di `ACCESS_BACKGROUND_LOCATION` e la presenza di `com.android.vending.BILLING`. Il manifest unito in `build/` è di una build vecchia e non lo contiene ancora.
- [ ] Pubblico di destinazione: **solo 18+**. Questionario IARC (§E). Annunci: no.
- [ ] Accesso all'app: "nessuna restrizione d'accesso" (niente login), con le istruzioni: la **demo dichiarata** ("Come funziona? Prova la demo", tutta sul telefono) per vedere il flusso con un solo dispositivo, e due dispositivi vicini per il servizio vero (stesso testo di [store_privacy.md](store_privacy.md) §D).
- [ ] Prodotto in-app attivo, test delle licenze, service account con i permessi.
- [ ] Integrità dell'app: progetto Google Cloud collegato, Play Integrity API abilitata.

## 6. Test su dispositivi reali (da report precedenti e da questa revisione)

Annotare per ciascuno il modello di dispositivo, la versione dell'OS e l'esito.

- [ ] **Face check**: Android (`android.media.FaceDetector`, più vecchio e meno tollerante di ML Kit: provarlo su almeno 3-4 marche, Samsung compresa) e iPhone (Apple Vision) con selfie normale, poca luce, controluce, occhiali (anche da sole), volto girato o inclinato, viso parzialmente fuori inquadratura, senza volto, foto di uno schermo; selfie verticale e orizzontale (orientamento EXIF). Annotare i falsi negativi: le soglie si regolano in `FaceDetectionChannel.kt` (`MIN_CONFIDENCE`, `MIN_FACE_WIDTH_RATIO`, `MAX_LONG_SIDE`). Il file temporaneo non resta nella cache (`raen_face_check_*`).
- [ ] **Selfie**: nessuna copia in galleria su più marche Android (alcune app fotocamera di sistema la salvano); flip; nessun EXIF nella foto ricevuta dall'altro telefono.
- [ ] **FLAG_SECURE** (Android): screenshot bloccato, registrazione dello schermo nera, cast nero, anteprima nera nei recenti.
- [ ] **PrivacyCover** (iOS): selettore delle app coperto in blu; i dialoghi di permesso di posizione e fotocamera **non** finiscono su schermo blu; il contenuto torna al rientro.
- [ ] **Ritorno in primo piano**: dopo 10 s, 60 s e 3 minuti in background; `checkAlive` e riconnessione; su Android si resta visibili con la notifica; su iOS si sparisce entro circa 90 s.
- [ ] **End durante una riconnessione** (modalità aereo, poi End): il partner vede la fine del match.
- [ ] **Pagamenti sandbox** Apple e Google: riuscito, annullato, in attesa ("Chiedi di acquistare", carta lenta), server spento durante l'acquisto, rimborso che revoca, secondo acquisto dopo la scadenza.
- [ ] **Attestazione** in `log` su TestFlight e sul test interno di Play: esiti `valid`; APK installato a mano → `unrecognizedApp`; simulatore → `missing`.
- [ ] **Reinstallazione su iOS**: profilo e token cancellati (`WipeDataFromPreviousInstallUseCase`).
- [ ] **Backup e trasferimento** (Android 12+): profilo e token non passano a un nuovo telefono.
- [ ] **Blocca e segnala** tra due telefoni; chiusura automatica con 3 telefoni su 2 reti; record creato, visibile da `/admin/reports`, cancellato con `DELETE` e dalla pulizia dopo 30 giorni (orologio simulato nei test del server).
- [ ] **Profilo**: consenso richiesto salvo il percorso neutro; "Cancella profilo" da online chiude prima la sessione; da online, cambiare genere, chi cerchi o "mostra il mio genere" chiede conferma e chiude la sessione (sull'altro telefono la persona sparisce), cambiare lingue o intento predefinito no.
- [ ] **Avviso sulla posizione**: con il permesso non concesso, Start mostra l'avviso (testo Android con il background, testo iOS "solo con l'app aperta"); "Non ora" lascia offline senza richiesta di sistema; "Continua" e permesso negato lasciano offline con il link alle impostazioni; con il permesso già concesso l'avviso non compare.
- [ ] **TLS**: l'app in release rifiuta `http://`; il server con TLS a metà non parte.
- [ ] Prestazioni e batteria con il foreground service acceso per un'ora (Android) e con il wakelock dello schermo.
