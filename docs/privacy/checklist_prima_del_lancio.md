# Raen: checklist prima del lancio

> **Bozza tecnica, non consulenza legale.** Elenco operativo di ciò che resta da fare prima di pubblicare su App Store e Google Play, ricavato dal codice al commit `4f7cae1` e da [dpia.md](dpia.md). Spuntare ogni voce con data e responsabile. Le voci **[B]** sono bloccanti.

## 1. Legale e organizzazione

- [ ] **[B]** Compilare i dati del titolare in [registro_trattamenti.md](registro_trattamenti.md) e [informativa_bozza.md](informativa_bozza.md).
- [ ] **[B]** Far rivedere e approvare la [DPIA](dpia.md) dal consulente legale o dal DPO; decidere sui rischi residui (§6) e, se restano alti, valutare la consultazione preventiva del Garante (art. 36).
- [ ] Decidere sul **DPO** (art. 37) e, se il titolare non è stabilito nell'UE, sul **rappresentante UE** (art. 27).
- [ ] **[B]** Scegliere l'**hosting** (raccomandato nell'UE), firmare il **contratto art. 28**, controllare i sub-responsabili e dove finiscono i backup (la cartella dei record di moderazione non deve stare nello stesso backup della `MODERATION_KEY`).
- [ ] Qualificare il ruolo di **Apple e Google** per servizio (distribuzione, pagamenti, App Attest, Play Integrity, telemetria ML Kit) e i **trasferimenti extra UE** (DPF o clausole tipo).
- [ ] Valutare l'art. 5(3) ePrivacy / art. 122 Codice privacy per la telemetria ML Kit e per l'attestazione del dispositivo.
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
- [ ] **[B]** **Link all'informativa privacy** in app: menu laterale ("Informazioni" o "Sicurezza e segnalazioni") e onboarding del profilo, accanto al consenso. Stringhe negli ARB di tutte le lingue, poi `flutter gen-l10n`.
- [ ] **[B, Android]** **Informativa in evidenza** sulla posizione anche in background, **prima** della richiesta del permesso (testo in [store_privacy.md](store_privacy.md) §C).
- [ ] Ritiro del consenso immediato: se una modifica del profilo da online ritira il consenso o cambia genere/preferenza, proporre o fare End (DPIA D4; oggi `changes_apply_from_your_next_start`).
- [ ] Salvare la **versione del consenso** al dato sensibile nel profilo, come `acceptedTermsVersion` (DPIA D5).
- [ ] Valutare `android.media.FaceDetector` al posto di ML Kit per togliere la telemetria Google (DPIA §6.7).
- [ ] Facoltativo: commenti sulle "distanze" in `MainActivity.kt:12-13` e `AppDelegate.swift:31`; pulizia di `Hotspot.memberSessionIds` a fine sessione (DPIA D8, D9).
- [ ] **[B, Android]** **Firma di release**: `android/app/build.gradle.kts` firma la release con le chiavi di **debug** (`signingConfigs.getByName("debug")`). Serve una keystore di upload e Play App Signing.
- [ ] **[B]** **JDK**: `android/gradle.properties` fissa `org.gradle.java.home` a `C:\Users\sepehrbaradaran\.jdks\azul-17.0.16` (una macchina Windows). Sulla macchina o CI che fa la build di release va adattato (percorsi in `macchine_sviluppo.md`), senza committare un percorso di un'altra macchina.
- [ ] Build di release con: `--dart-define=API_BASE_URL=https://<server>` (obbligatorio, solo https), `REAL_PAYMENTS=true`, `IOS_UNLOCK_PRODUCT_ID`/`ANDROID_UNLOCK_PRODUCT_ID` (oggi `TODO_REPLACE_…` in `lib/core/config/store_config.dart`), `GOOGLE_CLOUD_PROJECT_NUMBER` (per Play Integrity).
- [ ] iOS: capability **App Attest** sull'App ID; entitlement `production` già in `ios/Runner/Runner.entitlements`.

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
- [ ] Note di revisione (§D) con video o disponibilità a una prova dal vivo; contatto per la revisione.

**Google Play**
- [ ] **[B]** Data safety come in [store_privacy.md](store_privacy.md) §B (comprese telemetria ML Kit e Play Integrity).
- [ ] **[B]** Dichiarazione dei **servizi in primo piano** (tipo "Posizione") con video (§C).
- [ ] Verificare sull'AAB finale (Esplora app bundle) l'**assenza** di `ACCESS_BACKGROUND_LOCATION` e la presenza di `com.android.vending.BILLING`. Il manifest unito in `build/` è di una build vecchia e non lo contiene ancora.
- [ ] Pubblico di destinazione: **solo 18+**. Questionario IARC (§E). Annunci: no.
- [ ] Accesso all'app: "nessuna restrizione d'accesso" (niente login), con le istruzioni per vedere altre persone (servono due dispositivi).
- [ ] Prodotto in-app attivo, test delle licenze, service account con i permessi.
- [ ] Integrità dell'app: progetto Google Cloud collegato, Play Integrity API abilitata.

## 6. Test su dispositivi reali (da report precedenti e da questa revisione)

Annotare per ciascuno il modello di dispositivo, la versione dell'OS e l'esito.

- [ ] **Face check**: Android (ML Kit) e iPhone (Apple Vision) con selfie normale, senza volto, controluce, foto di uno schermo; il file temporaneo non resta nella cache (`raen_face_check_*`).
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
- [ ] **Profilo**: consenso richiesto salvo il percorso neutro; "Cancella profilo" da online chiude prima la sessione.
- [ ] **TLS**: l'app in release rifiuta `http://`; il server con TLS a metà non parte.
- [ ] Prestazioni e batteria con il foreground service acceso per un'ora (Android) e con il wakelock dello schermo.
