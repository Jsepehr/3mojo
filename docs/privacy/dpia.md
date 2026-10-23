# Raen: valutazione d'impatto sulla protezione dei dati (art. 35 GDPR)

> **Bozza tecnica, non consulenza legale.** L'ha scritta chi conosce il codice, per un consulente legale o un DPO che deve rivederla, completarla e approvarla. Le affermazioni tecniche sono state controllate sul codice del repository alla data indicata sotto. Le qualificazioni giuridiche (basi giuridiche, ruoli di Apple e Google, necessità del DPO) sono proposte da validare.

| | |
|---|---|
| Titolare del trattamento | **[DA COMPILARE: ragione sociale, sede, P.IVA, contatto privacy]** |
| DPO | **[DA DECIDERE, vedi §8]** |
| Prodotto | App "Raen" (Android, iOS), pacchetto `threemojo_app`, bundle/application id `com.threemojo.app`. Server `threemojo_server` (Dart Frog) |
| Stato del codice | Ramo `main`, commit `4f7cae1` (ottobre 2026), più le modifiche della versione 0.2: ML Kit tolto (il volto su Android lo rileva `android.media.FaceDetector` del sistema), firma della release Android con chiavi proprie, pulizia dei membri degli hotspot a fine sessione, informativa privacy in app, avviso in evidenza prima del permesso di posizione, ritiro del consenso immediato da online, consenso al dato sensibile versionato. Pagamenti in-app simulati, verifica del dispositivo spenta (`ATTESTATION_MODE=off`) |
| Versione del documento | 0.2, bozza del 23/10/2026 (0.1: stessa data, prima della rimozione di ML Kit) |
| Revisione prevista | Prima del lancio, poi a ogni modifica di ciò che viene raccolto, mostrato o conservato (vedi §9) |

Documenti collegati: [registro_trattamenti.md](registro_trattamenti.md), [informativa_bozza.md](informativa_bozza.md), [store_privacy.md](store_privacy.md), [checklist_prima_del_lancio.md](checklist_prima_del_lancio.md).

---

## 1. Perché serve una DPIA

Un solo motivo basterebbe. Qui ce ne sono diversi:

- **Dati di categoria particolare su scala potenzialmente ampia** (art. 35(3)(b)). Genere più "chi vuoi incontrare" lasciano dedurre l'orientamento sessuale. La Corte di giustizia (C‑184/20, *OT*, 1° agosto 2022) considera "particolari" anche i dati che rivelano l'orientamento in modo indiretto.
- **Geolocalizzazione precisa in tempo reale**, anche con l'app in background su Android, usata per mettere fisicamente in contatto degli sconosciuti.
- **Interessati potenzialmente vulnerabili**: minori che mentono sull'età, persone esposte a molestie o stalking, persone LGBTQ+ in contesti ostili.
- **Uso innovativo** che combina posizione, foto del volto e preferenze, con incontri di persona come risultato.
- **Decisioni automatiche con effetti sulla persona**: chiusura automatica della sessione dopo più segnalazioni e blocco temporaneo dei nuovi Start dagli stessi IP.

Da verificare con il consulente: la corrispondenza con le voci dell'elenco del Garante dei trattamenti soggetti a DPIA (provv. n. 467 dell'11 ottobre 2018) e con i criteri WP248 rev.01. Probabilmente se ne applicano almeno quattro: dati sensibili, dati di localizzazione, soggetti vulnerabili, tecnologie innovative.

## 2. Descrizione sistematica del trattamento

### 2.1 Cosa fa l'app

Raen mostra le persone fisicamente vicine (entro 100 m, o 200 m dentro uno stesso "posto affollato" rilevato dal server) che sono online nello stesso momento, si cercano a vicenda e sono ferme da almeno un minuto. Una persona va online con **Start** (selfie del momento più profilo) e ne esce con **End**. Non esistono account, nomi, email, numeri di telefono o identificativi permanenti. Da una foto si manda una richiesta d'incontro con una proposta scelta da una lista chiusa. Se l'altra persona accetta, nasce un match con chat. Un solo incontro alla volta.

### 2.2 Flussi di dati

```
Telefono A                                Server (RAM)                       Telefono B
─────────                                 ────────────                       ─────────
profilo cifrato (Keystore/Keychain)
selfie (solo byte in RAM)
GPS ── presence {lat,lng,gender,      ──▶ Session: posizione grezza +
       lookingFor,intent,languages,       ancora, profilo, selfie,
       showGender,selfie,unlockToken?}    token, IP (per i limiti)
                                          │ matching reciproco, 100 m,
                                          │ fermi da 1 min, fasce di 25 m
                                          └─▶ nearby {pseudonimo, stadio,  ──▶ in RAM, cache
                                               locked, selfie?, intent?,         svuotata a End
                                               languages?, gender?}
richiesta / risposta / chat           ──▶ inoltro, nessun salvataggio    ──▶ in RAM
block / report                        ──▶ BlockStore, ModerationStore (RAM)
                                          └─▶ record di moderazione cifrato su disco,
                                               30 giorni (selfie del segnalato, motivi,
                                               conteggio, ora al minuto)
acquisto (App Store / Play)          ──▶ /paywall/purchase: verifica col negozio,
                                          token casuale 2 h, HMAC della transazione 8 giorni
App Attest / Play Integrity (spenta) ──▶ verifica presso Apple/Google, nulla conservato
controllo del volto (sul telefono)   ──▶ nessuna rete: Apple Vision (iOS), android.media.FaceDetector (Android)
Play Billing Library (solo Android)  ──▶ possibile diagnostica verso Google (da verificare, §6.7)
```

Protocollo completo: `server/routes/ws.dart`. Comportamento del server: `server/README.md`. Architettura: `guida_per_sviluppatori.md` §3-4.

### 2.3 Tabella dei trattamenti

Legenda: **T** = telefono di chi usa l'app; **S** = server (in RAM salvo dove indicato); **Altri** = altri utenti. "Sessione" = da Start a End. A queste si aggiungono 45 s di grazia dopo una caduta di rete (la sessione è nascosta) e la chiusura automatica dopo 90 s senza messaggi.

| # | Dato | Finalità | Base giuridica (art. 6) | Art. 9 | Dove vive | Conservazione | Destinatari / responsabili |
|---|---|---|---|---|---|---|---|
| 1 | **Posizione precisa** (lat/lng, letture GPS, "ancora" mediana) | Mostrare chi è vicino e mostrare la persona a chi è vicino; controllo di plausibilità degli spostamenti; rilevamento dei posti affollati | 6(1)(b), servizio richiesto. Il permesso del sistema operativo non è un consenso GDPR | No (da valutare se insieme al n. 3 riveli frequentazioni di luoghi sensibili) | T: non salvata (stream `geolocator`). S: `Session` in `SessionStore` | Sessione. Una lettura utile ogni 10 s, poche letture recenti. Il centro di un posto affollato resta al più ~1 h (rinnovabile), con gli id interni dei membri | Nessun altro utente riceve coordinate o distanze. Hosting (responsabile art. 28) |
| 2 | **Selfie della sessione** (JPEG, 640 px, senza metadati) | Farsi riconoscere di persona dalle persone vicine; moderazione | 6(1)(b) | No: nessun trattamento biometrico (considerando 51). Il controllo del volto è solo sul telefono | T: solo byte in RAM, file della fotocamera cancellato subito. S: `Session` | Sessione. Sugli altri telefoni in RAM fino al loro End (cache svuotata) | Altri utenti compatibili in "Vicinanze" (salvo dietro paywall), controparte delle richieste e del match. Hosting |
| 3 | **Genere e "chi vuoi incontrare"** | Matching reciproco | 6(1)(b) | **Sì, 9(2)(a)**: consenso esplicito in app (`SaveProfileUseCase`), non richiesto nel percorso neutro "preferisco non dirlo" più "tutti" | T: profilo cifrato (`flutter_secure_storage`). S: fissato alla nascita della sessione | T: fino alla cancellazione del profilo o dell'app (anche dopo una reinstallazione su iOS, `WipeDataFromPreviousInstallUseCase`). S: sessione | "Chi cerchi" a nessuno. Il genere solo se la persona attiva "mostra il mio genere". **Inferenza**: chi ti vede sa che rientra in ciò che cerchi. Hosting |
| 4 | Intento, lingue (max 2), "mostra il mio genere" | Mostrare cosa si cerca stasera e che lingua si parla | 6(1)(b) | No | Come il n. 3 | Come il n. 3 | Altri utenti in "Vicinanze", richieste, match |
| 5 | Conferma 18+, versione del testo del consenso al dato sensibile accettata (`acceptedSensitiveConsentVersion`), versione dei termini accettati | Requisiti d'accesso; prova del consenso | 6(1)(b); 6(1)(c)/art. 7(1) per la prova del consenso | — | Solo T (profilo cifrato). Non va al server | Come il profilo | Nessuno |
| 6 | **Stadio di permanenza** (`meetingChance`: basso, medio o alto, da 1, 3 o 5 minuti fermi) | Indicare la probabilità d'incontro | 6(1)(b) | No | S: calcolato | Sessione | Altri utenti in "Vicinanze" |
| 7 | **Richieste d'incontro** (proposta da lista chiusa, stato) | Proporre e accettare un incontro; "un incontro alla volta"; "una richiesta per coppia" | 6(1)(b) | No | S: `EncounterStore`. T: RAM | Sessione. L'ultima proposta scelta è in RAM sul telefono, azzerata a End | La controparte. Il rifiuto è visibile a chi ha chiesto |
| 8 | **Messaggi della chat** (testo ≤ 1000 unità UTF-16, ora del server) | Comunicare con il match | 6(1)(b) | No (contenuto libero: può contenerne, a scelta dell'utente) | S: solo inoltro (`ConnectionHub.relayChatMessage`), mai salvati. T: RAM | T: fino a fine match o End. S: nessuna | Il partner del match. Hosting (transito) |
| 9 | **Blocchi** | Non vedersi più | 6(1)(b) e 6(1)(f) (sicurezza) | No | S: `BlockStore`. T: RAM | Sessione di chi blocca | Nessuno. Chi è bloccato non viene avvisato |
| 10 | **Segnalazioni** (motivo da lista chiusa, id interni di chi segnala, IP di chi segnala) | Chiusura automatica dopo segnalazioni da ≥ 3 sessioni e ≥ 2 IP | 6(1)(f), sicurezza degli utenti; eventualmente 6(1)(c) se si applica il DSA (vedi §8) | No | S: `ModerationStore` (RAM) | Finché vive la sessione segnalata | Nessuno |
| 11 | **Record di moderazione** (id casuale, selfie del segnalato, motivi con conteggio, numero di segnalazioni, se è scattata la chiusura, creazione e aggiornamento al minuto) | Revisione umana, ricorsi, misure contro gli abusi | 6(1)(f); eventualmente 6(1)(c) (DSA) | No (il selfie non viene trattato con mezzi biometrici) | S: **su disco**, cifrato AES-256-GCM (`ModerationRecordStore`, `MODERATION_KEY`) | **30 giorni** dalla creazione (pulizia all'avvio e ogni ora), o prima con cancellazione manuale dopo la revisione | Personale incaricato della moderazione (endpoint `/admin/reports`, `ADMIN_TOKEN`). Hosting |
| 12 | **Indirizzo IP** | Limiti contro gli abusi (nuovi Start, acquisti, attestazioni, admin); soglia dei 2 IP; cooldown dopo una chiusura automatica | 6(1)(f), sicurezza | No | S: RAM | Finestre di 10 min (limiti), 1 min (attestazioni), sessione (≤ 5 IP per sessione), **30 min** di cooldown (`MODERATION_COOLDOWN_MINUTES`). **Non** nel record di moderazione | Hosting. **Reverse proxy e log dell'infrastruttura: da configurare**, vedi §7 |
| 13 | **Segreto di sessione** (UUID v4 a ogni Start), id interno, pseudonimi per osservatore | Autenticare il socket; non esporre id stabili | 6(1)(b) | No | T: RAM. S: `SessionCredentials`, `Pseudonyms` | Sessione | Gli altri vedono solo uno pseudonimo diverso per ciascuno |
| 14 | **Token di sblocco** (casuale, 2 h) | Sblocco a pagamento | 6(1)(b) | No | T: cifrato, solo finché vale. S: `PaywallStore` | 2 ore | Nessuno |
| 15 | **Dati d'acquisto** (piattaforma, prodotto, transazione firmata o `purchaseToken`) | Verificare il pagamento ed emettere il token una sola volta; revocarlo in caso di rimborso | 6(1)(b) | No | S: durante la verifica; poi solo **HMAC** di `piattaforma:transazione`, data e token finché vale (`RedeemedTransactions`) | HMAC e data **8 giorni** (RAM: si perdono al riavvio) | Apple e Google (pagamento, verifica, notifiche di rimborso). Oggi **simulato** |
| 16 | **Attestazione del dispositivo** (App Attest: chiave nuova a ogni sessione; Play Integrity: token Standard) | Rendere costose le sessioni parallele da script | 6(1)(f), prevenzione degli abusi. Da valutare l'art. 5(3) ePrivacy, vedi §8 | No | S: solo durante la verifica, poi esito e contatori | Nulla di conservato; orari delle attestazioni per IP per 1 min | Apple, Google (verdetto). **Oggi spenta** |
| 17 | **Diagnostica della Play Billing Library** (solo Android, **da verificare**): contenuto non documentato da noi; la libreria include il trasporto di log di Google | Diagnostica **di Google** sul proprio SDK di pagamento | Da qualificare (vedi §8). Non la riceviamo noi | No | Telefono → Google (HTTPS, `com.google.android.datatransport`) | Secondo Google | Google. Fino alla versione 0.1 qui c'era la telemetria di ML Kit (con un identificativo per installazione), **tolta**: il controllo del volto non usa più librerie Google né la rete |
| 18 | Impostazioni (lingua, tema), segno d'installazione | Preferenze; pulizia del Keychain dopo una reinstallazione | Dati che restano sul telefono | — | Solo T (`shared_preferences`) | Fino alla disinstallazione | Nessuno |
| 19 | **Email al contatto di sicurezza** | Segnalazioni, ricorsi, richieste di cancellazione di un record | 6(1)(f) / 6(1)(c) | Possibile, a scelta di chi scrive | Casella email (fornitore da scegliere) | **[DA DEFINIRE]** | Fornitore email (responsabile art. 28) |

Cosa **non** si raccoglie, verificato sul codice: nome, email, telefono, data di nascita, contatti, galleria (solo fotocamera, `ImageSource.camera`), id pubblicitari, id fissi del dispositivo (il vecchio `deviceId` viene cancellato da `UnlockTokenStore`), analytics, crash reporting, font scaricati da Google (Manrope è incluso nell'app), dati biometrici (né sul telefono né sul server: `SelfieValidator` non decodifica i pixel), chat su disco (`purgeLegacyChatStorage` cancella quelle delle versioni vecchie), distanze verso il client.

### 2.4 Risorse e tecnologie

- **App**: Flutter, Provider. Pacchetti che toccano dati personali: `geolocator` (GPS, foreground service su Android), `image_picker` (fotocamera frontale), `flutter_secure_storage`, `shared_preferences`, `web_socket_channel`, `in_app_purchase`. Canali nativi propri: `raen/face_detection` (`android.media.FaceDetector` del sistema Android, nessuna libreria e nessuna rete; Apple Vision su iOS) e `raen/attestation` (`com.google.android.play:integrity:1.6.0`; DeviceCheck/App Attest).
- **Server**: Dart Frog, un processo, stato in RAM. Unica persistenza: la cartella `MODERATION_DIR`. TLS diretto (`TLS_CERT_PATH`/`TLS_KEY_PATH`) o tramite reverse proxy. L'app in release accetta solo `https://` (`lib/core/network/api_config.dart`).
- **Hosting**: **[DA DECIDERE]**, vedi §8.

## 3. Necessità e proporzionalità

| Principio | Come è rispettato | Dove nel codice |
|---|---|---|
| Minimizzazione | Nessun account né dato anagrafico. Al server va solo ciò che serve al matching (`PresenceProfileModel`: mai conferma d'età né consenso). Al client nessuna coordinata né distanza. Liste chiuse per intento, proposte e motivi di segnalazione: niente testo libero, salvo la chat | `lib/features/nearby/data/models/presence_profile_model.dart`; `server/lib/src/session_store.dart:163-171` (`toJson`) |
| Limitazione della conservazione | Tutto in RAM e legato alla sessione. L'unica eccezione su disco è il record di moderazione, 30 giorni. Profilo solo sul telefono | `server/lib/src/session_lifecycle.dart` (`endNow`); `server/lib/src/moderation_records.dart:158` |
| Esattezza | Profilo modificabile dal menu. Selfie nuovo a ogni Start. Ancora mediana contro gli errori del GPS | `ui_profile.dart`; `session_store.dart` (ancore) |
| Integrità e riservatezza | TLS obbligatorio in release. Segreto solo nel primo messaggio, mai nell'URL. Profilo e token cifrati sul telefono. Record cifrati AES-256-GCM. Endpoint admin solo su TLS, con token di almeno 32 caratteri e confronto a tempo costante | `api_config.dart`; `realtime_connection.dart`; `profile_local_data_source_impl.dart`; `admin_reports_api.dart` |
| Trasparenza | Testi dei permessi iOS. Consenso esplicito con l'avvertenza dell'inferenza. Pagina "Sicurezza e segnalazioni". Termini d'uso. **Informativa privacy in app** (menu, "Informazioni", profilo, termini), con versione e data. **Avviso in evidenza** sulla posizione prima del permesso di sistema, con testo diverso per Android (anche in background) e iOS (solo con l'app aperta). Manca ancora l'URL pubblico dell'informativa (D2) | `ios/Runner/*.lproj/InfoPlist.strings`; `lib/l10n/app_*.arb`; `lib/features/safety/presentation/pages/ui_privacy_policy.dart`; `lib/core/config/privacy_policy_info.dart`; `lib/features/nearby/presentation/pages/ui_location_disclosure.dart` |
| Alternative meno invasive valutate | Distanza al client (scartata: permette di trilaterare). Id stabili (scartati: pseudonimi per osservatore). Chat salvate (scartate). Assertion App Attest (scartate: richiedono un id stabile). Face detection sul server (scartata: on-device). Font scaricato da Google (scartato) | `guida_per_sviluppatori.md` §3.2, §3.9 |

**Proporzionalità della posizione precisa**: il servizio è proprio l'incontro con chi è vicino adesso, quindi una posizione approssimata (per esempio ~1 km) non lo renderebbe possibile. La precisione serve però **solo al server**. Al client arrivano solo lo pseudonimo, lo stadio di permanenza e l'ordine per fasce di 25 m. La posizione in background (solo Android) serve a non sparire appena si blocca lo schermo. È limitata alla sessione, segnalata da una notifica persistente e si spegne con End.

**Proporzionalità del record di moderazione**: senza la foto non si può giudicare "foto falsa", "inappropriata" o "sembra minorenne". Niente posizione, chat, IP né id. 30 giorni è un periodo breve. Da decidere con il consulente se 30 giorni bastano anche per i ricorsi e per eventuali richieste delle autorità.

## 4. Rischi per gli interessati

Scala (come nel metodo CNIL): **probabilità** Trascurabile / Limitata / Significativa / Massima; **gravità** Trascurabile / Limitata / Significativa / Massima. "Prima" = senza le misure del §5; "dopo" = con le misure già nel codice e la configurazione di produzione raccomandata (TLS, `TRUSTED_PROXY`, `MODERATION_KEY`, `ADMIN_TOKEN`), **ma con l'attestazione spenta**.

| # | Rischio | Gravità | Prob. prima | Prob. dopo | Misure principali (§5) | Residuo (§6) |
|---|---|---|---|---|---|---|
| R1 | **Stalking e localizzazione fine**: risalire a dove si trova una persona, anche con GPS falso o più sessioni | Massima | Massima | **Limitata** (resta il "è entro 100 m da me", che è il servizio stesso) | M1, M2, M3, M4, M5, M9, M14 | §6.1, §6.2 |
| R2 | **Outing dell'orientamento**: dedurre chi cerca chi, per chi guarda, chi sonda con più sessioni, chi prende il telefono o fa screenshot | Massima | Significativa | **Limitata** | M6, M7, M10, M11, M12, M13 | §6.1, §6.3 |
| R3 | **Molestie**: richieste o messaggi molesti, inseguimento fisico dopo un rifiuto o un match | Significativa | Significativa | **Limitata / Significativa** | M8, M15, M16, M17 | §6.5 |
| R4 | **Minori** che usano un'app di incontri con sconosciuti adulti vicini | Massima | Significativa | **Significativa** (solo autodichiarazione) | M18, M16, M17 | §6.6 |
| R5 | **Foto altrui**, impersonificazione, foto inappropriate | Significativa | Significativa | **Limitata** | M19, M16, M17 | §6.6 |
| R6 | **Profilazione e tracciamento tra sessioni** (da parte nostra, di terzi o degli altri utenti) | Significativa | Limitata | **Trascurabile** (nostra) / **Limitata** (telemetria Google) | M6, M20, M21, M22 | §6.7 |
| R7 | **Diffusione di selfie o chat** da parte di chi le riceve | Significativa | Significativa | **Significativa su iOS** (screenshot possibili), **Limitata su Android** | M11, M12, M13 | §6.3 |
| R8 | **Violazione del server** (intrusione, dump della memoria, furto del disco) | Massima | Limitata | **Limitata**. Impatto ridotto dall'assenza di storico: si espone solo chi è online in quel momento | M23, M24, M25 | §6.4 |
| R9 | **Abuso delle segnalazioni ed esclusioni ingiuste**: chiusure coordinate, cooldown che colpisce tutto un IP condiviso | Limitata | Significativa | **Limitata** | M16, M26 | §6.5 |
| R10 | **Impossibilità di esercitare i diritti** (senza account non si identifica l'interessato) | Limitata | Massima | **Limitata** (i diritti si esercitano soprattutto da sé, sul telefono) | M27 | §6.8 |

## 5. Misure tecniche già implementate

| Id | Misura | File |
|---|---|---|
| M1 | **Nessuna distanza al client** né coordinate: solo pseudonimo, stadio, `locked`, selfie, intento, lingue, genere se mostrato | `server/lib/src/session_store.dart:163-171`; `lib/features/nearby/domain/entities/nearby_person.dart` |
| M2 | **Ancora e osservatore fermo**: distanze da ancora ad ancora (mediana delle prime letture, poi congelata). Uno spostamento conta solo oltre 60 m per 2 letture di fila. Anche chi guarda deve essere fermo da 1 minuto. Ogni "campione" utile per sondare costa ≥ ~80 s | `server/lib/src/session_store.dart:212-225`; test "the viewer must stay put too" in `server/test/src/session_store_test.dart` |
| M3 | **Ordine per fasce di 25 m** con un ordine fisso per osservatore dentro la fascia | `session_store.dart` (`rankBandMeters`) |
| M4 | **Limiti sulla posizione**: al più una ogni 10 s; salti oltre 50 m/s più 250 m scartati (`implausibleMovement`); al più una lista diversa ogni 5 s per osservatore | `session_store.dart` (`upsertPosition`, `minPositionInterval`); `server/lib/src/connection_hub.dart:92` |
| M5 | **Raggio solo sul server** (100 m, 200 m nello stesso posto affollato). Il client non lo conosce e non rifiltra | `connection_hub.dart:69`; `server/lib/src/hotspot_store.dart` |
| M6 | **Pseudonimi per osservatore**: la stessa persona ha un id diverso per ognuno. Due telefoni non possono confrontare le liste. Dimenticati a fine sessione | `server/lib/src/pseudonyms.dart`; `server/lib/src/session_credentials.dart` |
| M7 | **Matching reciproco** e "chi cerchi" mai inviato ad altri. Profilo e selfie **fissati alla nascita della sessione**: non si può sondare cambiando genere a sessione aperta | `server/lib/src/presence_profile.dart:95`; `server/lib/src/realtime_message_handler.dart` (presence) |
| M8 | **Blocco** nei due sensi, per tutta la sessione di chi blocca, senza avviso. Chi è bloccato vede quello che vedrebbe se l'altro avesse premuto End | `server/lib/src/block_store.dart`; `lib/features/safety/` |
| M9 | **Limite ai nuovi Start**: 20 per IP ogni 10 minuti | `server/lib/src/new_session_rate_limiter.dart` |
| M10 | **Profilo cifrato sul telefono** (Keystore / Keychain `first_unlock_this_device`). Niente backup cloud né trasferimento tra dispositivi (`allowBackup="false"`, `data_extraction_rules.xml`). Pulizia del Keychain dopo una reinstallazione | `lib/features/profile/data/datasources/profile_local_data_source_impl.dart`; `android/app/src/main/AndroidManifest.xml`; `android/app/src/main/res/xml/data_extraction_rules.xml`; `lib/features/profile/domain/usecases/wipe_data_from_previous_install_usecase.dart` |
| M11 | **FLAG_SECURE** su tutta l'app Android: niente screenshot, registrazioni o cast; anteprima nera nel multitasking | `android/app/src/main/kotlin/com/threemojo/app/MainActivity.kt:19-22` |
| M12 | **PrivacyCover** su iOS: copre l'app nel selettore del multitasking quando va in background | `ios/Runner/AppDelegate.swift:47-89` |
| M13 | **Nessuna traccia in memoria dopo End**: selfie solo come byte, cache delle immagini e delle foto ricevute svuotate, chat solo in RAM | `lib/features/session/presentation/providers/pro_session.dart:112`; `lib/core/utils/photo_bytes_cache.dart`; `lib/features/chat/data/datasources/chat_remote_data_source_impl.dart` |
| M14 | **Paywall deciso dal server**: le persone dietro il paywall arrivano senza foto | `session_store.dart:700` (`_withPaywallVisibility`) |
| M15 | **Un incontro alla volta**, una richiesta per coppia per sessione, al più 5 pendenti in uscita e 20 in entrata, proposte da lista chiusa, chat solo con un match attivo | `server/lib/src/encounter_store.dart`; `server/lib/src/encounter_proposal.dart` |
| M16 | **Segnalazione** con motivi chiusi (tra cui `underage` e `fakePhoto`), al più 5 per sessione. Chiusura automatica da ≥ 3 sessioni e ≥ 2 IP. Cooldown breve e regolabile | `server/lib/src/moderation_store.dart`; `server/lib/src/report_reason.dart` |
| M17 | **Termini d'uso** obbligatori e versionati (tolleranza zero, 18+, solo la propria foto). Pagina "Sicurezza e segnalazioni" con il contatto | `lib/features/safety/presentation/widgets/cmp_terms_of_use.dart`; `lib/features/safety/presentation/pages/ui_safety.dart`; `lib/features/profile/domain/entities/profile.dart:37` |
| M18 | **Conferma 18+** obbligatoria, controllata nello use case | `lib/features/profile/domain/usecases/save_profile_usecase.dart:30` |
| M19 | **Selfie dalla fotocamera frontale soltanto** (niente galleria), controllo che ci sia un volto **sul telefono** (`android.media.FaceDetector` o Apple Vision, entrambi del sistema operativo e senza rete; il file temporaneo è cancellato sempre), file della fotocamera cancellato appena letto | `lib/features/session/data/datasources/selfie_local_data_source_impl.dart:37-42`; `lib/features/session/data/datasources/face_detector_io.dart`; `android/app/src/main/kotlin/com/threemojo/app/FaceDetectionChannel.kt` |
| M20 | **Niente id permanenti**: segreto nuovo a ogni Start, `deviceId` vecchio cancellato, token di sblocco casuale e valido solo 2 h, chiave App Attest nuova a ogni sessione e mai salvata | `lib/core/unlock/unlock_token_store.dart`; `ios/Runner/AppDelegate.swift:139-197` |
| M21 | **EXIF e metadati rimossi** due volte: sul telefono (`prepareSelfieForUpload`) e sul server (`SelfieValidator`, che non decodifica i pixel) | `lib/features/nearby/data/datasources/nearby_remote_data_source_impl.dart:324`; `server/lib/src/selfie_validator.dart` |
| M22 | **Nessun SDK di terzi** di analytics, crash o pubblicità. Font incluso nell'app. ML Kit tolto: il volto lo rileva il sistema operativo. Unica telemetria possibile: quella della Play Billing Library di Google su Android (da verificare, §6.7) | `pubspec.yaml`; `android/app/build.gradle.kts` |
| M23 | **Server senza storico**: in RAM, cancellato a ogni riavvio, salvo i record di moderazione cifrati. Endpoint di debug spento e senza posizioni. Log senza IP, token o contenuti | `server/README.md`; `server/lib/src/attestation/attestation_gate.dart`; `server/routes/paywall/purchase.dart` |
| M24 | **Cifratura dei record**: AES-256-GCM con l'id come dato autenticato, scrittura atomica, cartella con permessi `700`. Senza chiave non si salva nulla (mai una chiave di ripiego) | `server/lib/src/moderation_records.dart` |
| M25 | **TLS ovunque in produzione** e IP del client da `X-Forwarded-For` solo da proxy fidati | `server/main.dart`; `lib/core/network/api_config.dart`; `server/lib/src/client_ip.dart` |
| M26 | **Limiti per connessione** (token bucket, dimensione dei messaggi), limiti per IP su acquisti, admin e attestazioni | `server/lib/src/rate_limiters.dart`; `server/lib/src/realtime_message_handler.dart` (`maxCharsFor`) |
| M27 | **Cancellazione da sé**: End chiude subito la sessione sul server. "Cancella profilo" da online chiude prima la sessione e poi cancella; così anche una modifica da online di genere, chi cerchi, "mostra il mio genere" o che fa perdere il consenso (ritiro col percorso neutro), dopo una conferma. Disinstallare cancella tutto (anche il Keychain alla reinstallazione successiva) | `lib/features/session/domain/usecases/withdraw_profile_usecase.dart`; `update_profile_usecase.dart`; `end_session_usecase.dart` |
| M28 | **Verifica del dispositivo** (App Attest, Play Integrity) predisposta, fail-closed in `enforce`, senza assertion né id conservati. **Oggi spenta** | `server/lib/src/attestation/`; `lib/core/attestation/` |
| M29 | **Consenso versionato**: nel profilo cifrato la versione del testo accettato (`acceptedSensitiveConsentVersion`, attuale `Profile.currentSensitiveConsentVersion = 1`; i profili col vecchio booleano valgono 1). Se il testo cambia si alza la versione e il consenso va riconfermato al salvataggio e allo Start. Non va al server | `lib/features/profile/domain/entities/profile.dart`; `lib/features/profile/data/models/profile_model.dart`; `lib/features/profile/domain/usecases/renew_sensitive_consent_usecase.dart` |

## 6. Rischi residui

### 6.1 Sessioni parallele senza attestazione attiva
Con `ATTESTATION_MODE=off` uno script può aprire fino a 20 sessioni nuove ogni 10 minuti **per IP**, e con più IP (dati mobili, proxy) molte di più. Due abusi restano possibili:
- **Sondare l'orientamento**: aprire sessioni con generi e preferenze diverse e vedere in quali compare una persona. Il profilo fissato alla nascita e il minuto d'attesa rendono la cosa lenta ma non impossibile per chi è fisicamente vicino alla persona.
- **Localizzare con più punti**: più sessioni con GPS falso in punti diversi; l'intersezione dei cerchi da 100 m restringe l'area.

Mitigazione disponibile: `ATTESTATION_MODE=log` e poi `enforce` (guida §3.9). Anche con l'attestazione resta il caso di chi ha più telefoni veri. **Raccomandazione**: decidere prima del lancio se partire con `log` e passare a `enforce` dopo 1-2 settimane di metriche.

### 6.2 Oracolo lento (~80 s per campione)
Con un solo GPS falso, chi muove la propria ancora può ancora sapere se la persona è dentro o fuori un cerchio di 100 m, ma ogni prova costa almeno ~80 s (spostamento confermato più un minuto fermo). Bastano decine di minuti per restringere l'area a poche decine di metri, se la persona resta ferma. Il servizio rivela comunque per definizione "è entro 100 m da me": il rischio concreto è che lo sappia chi è fisicamente vicino, e quello è il prodotto.

### 6.3 Rango tramite `locked` e inferenze dagli altri utenti
- Senza sblocco, le persone `locked` sono i due terzi **più vicini** (`session_store.dart:700`). Sapere chi è bloccato dice "più vicino di quelli liberi". Le fasce di 25 m e l'assenza di distanze limitano l'effetto.
- **Chi ti vede sa che rientra in ciò che cerchi**: l'inferenza sull'orientamento verso gli altri utenti è intrinseca al matching reciproco. Il testo del consenso lo dice ("people who can see me may guess who I'm looking for").
- Su **iOS** gli screenshot non si possono impedire: selfie e chat possono essere salvati dai destinatari. Su Android `FLAG_SECURE` li blocca, ma non impedisce una foto con un secondo telefono.

### 6.4 Server
In RAM ci sono, per chi è online in quel momento: posizione precisa, selfie, genere e preferenza. Un'intrusione col processo in esecuzione li esporrebbe tutti. Misure da completare in produzione: hosting nell'UE, accessi amministrativi ristretti, niente core dump o swap non cifrato, aggiornamenti, monitoraggio. Vedi la checklist.

### 6.5 IP condivisi, cooldown e segnalazioni
- **IP condivisi** (Wi-Fi di un locale, CGNAT degli operatori): una chiusura automatica blocca per 30 minuti i nuovi Start di **tutti** dietro quell'IP. Le sessioni aperte non sono toccate. Il limite di 20 Start per IP ogni 10 minuti può colpire un locale molto affollato.
- **Segnalazioni coordinate**: 3 persone su 2 reti diverse possono far chiudere una sessione. È una decisione automatica con effetti (esclusione temporanea): da valutare rispetto all'art. 22 (probabilmente non "significativa", ma va offerto un ricorso umano, oggi l'email di sicurezza) e al DSA (motivazione della restrizione, reclamo).
- Dietro un reverse proxy **senza** `TRUSTED_PROXY` la condizione dei 2 IP non scatta mai e il cooldown colpirebbe il proxy, cioè tutti.

### 6.6 Minori e foto
- L'età è **solo autodichiarata**. Mitigazioni: classificazione 18+ negli store, motivo di segnalazione `underage`, record con la foto per la revisione. Da valutare con il consulente se servono misure di age assurance (anche alla luce delle linee guida europee sulla protezione dei minori online e dell'evoluzione normativa italiana sulla verifica dell'età).
- Il controllo del volto dice solo che c'è un volto: non che sia la persona che usa l'app (nessun liveness, nessun confronto). Una foto di uno schermo o di un'altra persona passa. Mitigazioni: fotocamera soltanto, motivo `fakePhoto`, termini.
- Su alcuni Android l'app fotocamera di sistema (aperta da `image_picker`) potrebbe salvare una copia anche in galleria: **da verificare** sui dispositivi di test.

### 6.7 Terze parti
- **ML Kit tolto** (versione 0.2): inviava a Google telemetria con un **identificativo per installazione**. Ora su Android il volto lo rileva `android.media.FaceDetector` del sistema operativo, sul dispositivo e senza rete. Il prezzo è la precisione: è un rilevatore più vecchio, meno tollerante con volti girati o inclinati e con poca luce. Un falso negativo impedisce lo Start a chi ha fatto un selfie vero (l'utente rifà la foto); un falso positivo lascia passare una foto senza volto, ma il controllo non è mai stato una verifica d'identità (§6.6). Soglie da regolare dopo le prove su telefoni veri (checklist §6).
- **Play Billing Library** (Android, `com.android.billingclient:billing`, portata da `in_app_purchase_android`) contiene e usa `com.google.android.datatransport` (sorgente di log `PLAY_BILLING_LIBRARY` nelle sue classi), quindi con ogni probabilità invia a Google diagnostica sul proprio funzionamento. **Da verificare** sulla documentazione di Google (Play SDK Index, guida Data safety per la Billing Library) e, se confermato, da dichiarare (Data safety, informativa). Non è evitabile finché ci sono acquisti in-app su Play.
- **App Attest / Play Integrity** (quando accese): Apple e Google trattano dati del dispositivo per il verdetto e sanno che quel dispositivo ha chiesto un'attestazione per Raen.
- **Acquisti in-app**: Apple e Google sanno chi ha comprato (il loro account). Noi no.

### 6.8 Diritti degli interessati senza account
Non potendo identificare l'interessato (art. 11 GDPR), i diritti di accesso, rettifica e cancellazione si esercitano soprattutto **da sé**. I dati del server si cancellano con End. Il profilo si vede, si modifica e si cancella dal menu. La disinstallazione cancella il resto. Per il **record di moderazione** l'interessato non ha nessun identificativo da indicarci: dovrebbe darci elementi per riconoscerlo (per esempio data e ora approssimate, e la propria foto per il confronto, cosa che a sua volta è un trattamento da regolare). Serve una procedura scritta (vedi §8). L'email di sicurezza è ancora un segnaposto (`lib/core/config/safety_contact.dart:12`).

### 6.9 Ritiro del consenso a sessione aperta
**Risolto nella versione 0.2** (era D4). Il server fissa il profilo alla nascita della sessione, quindi una modifica da online che tocca il dato sensibile (genere, chi cerchi, "mostra il mio genere", o la perdita del consenso al testo attuale, cioè il ritiro col percorso neutro "preferisco non dirlo" più "tutti") **chiude prima la sessione**, dopo una conferma in UI, e solo poi salva (`UpdateProfileUseCase`, in `session/`; testi `profile_save_ends_session_*`). Lingue e intento predefinito valgono dal prossimo Start (`profile_online_changes_hint`): non sono dati art. 9. "Cancella profilo" da online chiudeva già prima la sessione (`WithdrawProfileUseCase`). Art. 7(3): il ritiro è semplice quanto il conferimento e vale subito.

## 7. Divergenze tra codice e promesse trovate in questa revisione

| # | Dove | Cosa | Effetto | Proposta |
|---|---|---|---|---|
| D1 | `ios/Runner/PrivacyInfo.xcprivacy` (prima di questa revisione) | Tutti i tipi dichiarati "non collegati all'identità". Il selfie è una foto del volto, conservata 30 giorni se segnalato; posizione e profilo stanno nella stessa sessione del selfie. Mancava la cronologia acquisti | Etichetta App Store possibilmente inesatta | **Aggiornato** in questa revisione: `Linked = true` e `PurchaseHistory` aggiunta. Vedi `store_privacy.md` §A |
| D2 | App intera | **Nessuna informativa privacy** e nessun link in app (richiesta da Apple 5.1.1(i), da Google Play e dagli artt. 13-14) | Bloccante per il lancio | **In app risolto** nella versione 0.2: `UiPrivacyPolicy` (testi `privacy_*` negli ARB), dal menu, da "Informazioni", dal profilo (anche nell'onboarding, accanto a consenso e termini) e dai termini. **Resta da fare**: pubblicarla a un URL stabile e metterlo in `PrivacyPolicyInfo.publicUrl` (oggi il segnaposto `https://raen.example/privacy`) e nelle schede degli store |
| D3 | `lib/core/config/safety_contact.dart:12` | Contatto `safety@raen.example`, un dominio che non riceve posta | Nessun canale per ricorsi e diritti sui record | Casella vera e presidiata |
| D4 | `lib/features/profile/presentation/pages/ui_profile.dart` (riga con `changes_apply_from_your_next_start`) | Il ritiro del consenso con una modifica del profilo da online non ha effetto fino a End | Art. 7(3) | **Risolto** nella versione 0.2: `UpdateProfileUseCase` chiude prima la sessione, con conferma (§6.9) |
| D5 | `lib/features/profile/domain/entities/profile.dart:64` | Il consenso è un booleano senza versione del testo né data | Prova del consenso (art. 7(1)) debole se il testo cambia | **Risolto** nella versione 0.2: si salva la **versione** del testo accettato (`acceptedSensitiveConsentVersion`, `currentSensitiveConsentVersion = 1`), non la data; una versione vecchia va riconfermata (M29) |
| D6 | Flusso Start su Android | Nessuna **informativa in evidenza** prima della richiesta del permesso di posizione che dica che la posizione resta condivisa **anche con l'app in background** finché non si preme End. Lo dice solo la notifica persistente, dopo | Politica "Dati utente" di Google Play; trasparenza | **Risolto** nella versione 0.2: `UiLocationDisclosure` dopo il tap su Start, finché il permesso non è concesso, con "Continua" / "Non ora" e solo dopo la richiesta di sistema; su iOS con il testo "solo con l'app aperta" (`store_privacy.md` §C) |
| D7 | `android/app/build.gradle.kts` (commento) e informativa | La telemetria ML Kit (con un id per installazione) era documentata solo nel commento di build e nelle licenze, non per l'utente | Trasparenza | **Superato** nella versione 0.2: ML Kit tolto, e la bozza di informativa non lo cita più. Anche i testi in app (ARB `privacy_face_check_body` e `privacy_sharing_apple_google`) sono allineati. Resta da verificare la diagnostica della Play Billing Library (§6.7) |
| D8 | `android/app/src/main/kotlin/com/threemojo/app/MainActivity.kt:12-13`, `ios/Runner/AppDelegate.swift:31` | I commenti citano la "distanza" o le "distanze" mostrate: oggi non se ne mostra nessuna | Solo documentazione interna | **Corretto** nella versione 0.2 |
| D9 | `server/lib/src/hotspot_store.dart:45` con `session_lifecycle.dart:250-254` | `endNow` non toglie l'id interno della sessione da `Hotspot.memberSessionIds`: restano id interni orfani finché l'hotspot vive (1 h, rinnovabile) | Trascurabile: l'id interno non è più collegato a nulla | **Corretto** nella versione 0.2: `HotspotStore.forgetSession`, chiamata da `ConnectionHub.forgetSession` in `endNow` (test `server/test/src/session_lifecycle_hotspot_test.dart`) |
| D10 | `lib/l10n/app_*.arb` (`no_names_no_public_profile`) | "Gli altri vedono solo selfie, intento e lingue", ma vedono anche lo stadio di permanenza (basso/medio/alto) | Minimo | Citarlo nell'informativa (già fatto nella bozza) |

## 8. Piano d'azione e decisioni del titolare

### Da decidere (titolare, con il consulente)

1. **DPO** (art. 37): obbligatorio se le attività principali consistono in trattamenti su larga scala di categorie particolari o in un monitoraggio regolare e sistematico su larga scala. Raen tratta l'orientamento (art. 9) e la posizione in tempo reale come attività principale: se l'uso cresce è probabile che serva. Decidere ora, o fissare una soglia d'uso oltre la quale nominarlo.
2. **Rappresentante nell'UE** (art. 27): serve solo se il titolare non è stabilito nell'UE.
3. **Hosting nell'UE**: raccomandato (nessun trasferimento per il dato più delicato). Scegliere il fornitore, firmare il **contratto art. 28**, verificare i sub-responsabili e la localizzazione dei backup. La cartella dei record di moderazione non deve finire in backup non cifrati né insieme alla `MODERATION_KEY`.
4. **Apple e Google**: qualificare il ruolo per servizio (distribuzione, pagamenti, App Attest, Play Integrity, eventuale diagnostica della Play Billing Library; la telemetria ML Kit non c'è più): titolari autonomi o responsabili, secondo i rispettivi termini. Per la diagnostica della Billing Library, se confermata, valutare la contitolarità (logica della sentenza CGUE C‑40/17 *Fashion ID*) e l'art. 5(3) ePrivacy / art. 122 Codice privacy (accesso a informazioni sul terminale). Lo stesso vale per l'attestazione: è "strettamente necessaria"?
5. **Trasferimenti extra UE**: Apple e Google (USA), da verificare l'adesione aggiornata all'EU-U.S. Data Privacy Framework o le clausole contrattuali tipo dei loro termini. Un hosting extra UE richiederebbe una TIA.
6. **Base giuridica della posizione**: proposta 6(1)(b). In alternativa il consenso, che però renderebbe il servizio condizionato al consenso (art. 7(4)). Decidere e scriverlo nell'informativa.
7. **Durata dei record di moderazione** (30 giorni) e **procedura** per accesso, cancellazione e ricorso: chi revisiona, entro quanto, come si riconosce l'interessato senza id, cosa si risponde.
8. **DSA (Reg. UE 2022/2065)**: Raen mostra i selfie a una cerchia potenzialmente ampia di persone, quindi potrebbe rientrare tra le piattaforme online. Valutare gli obblighi (punto di contatto, meccanismo di segnalazione, motivazione delle restrizioni come la chiusura automatica, gestione dei reclami) e le esenzioni per micro e piccole imprese.
9. **Minori e verifica dell'età**: basta l'autodichiarazione più la segnalazione `underage`, o servono strumenti di age assurance?
10. **Conservazione dei log dell'infrastruttura** (reverse proxy, provider): IP e orari di ogni connessione. Raccomandazione: log di accesso spenti o ridotti, ≤ 7 giorni, senza query string.
11. **Gestione delle violazioni** (artt. 33-34): chi decide, entro 72 ore, con quale modello di notifica.

### Azioni tecniche raccomandate (versione 0.1, senza modifiche al codice; aggiornate nella 0.2)

| Priorità | Azione | Riferimento |
|---|---|---|
| Alta | Informativa privacy pubblicata a un URL stabile (il link in app c'è già) | D2 |
| Alta | Email di sicurezza vera | D3 |
| Alta | `ATTESTATION_MODE=log` al lancio, poi `enforce` con le metriche | §6.1 |
| Fatto (0.2) | `android.media.FaceDetector` al posto di ML Kit: niente più telemetria dal controllo del volto. Da provare su telefoni veri | §6.7 |
| Fatto (0.2) | Pulizia dei membri degli hotspot a fine sessione; commenti sulle distanze | D8, D9 |
| Fatto (0.2) | Informativa privacy in app, con link da menu, "Informazioni", profilo e termini | D2 |
| Fatto (0.2) | Informativa in evidenza sulla posizione prima del permesso (Android: anche in background; iOS: solo con l'app aperta) | D6 |
| Fatto (0.2) | Ritiro del consenso immediato anche con la modifica del profilo da online | D4, §6.9 |
| Fatto (0.2) | Versione del consenso salvata nel profilo | D5 |
| Media | Verificare cosa invia a Google la Play Billing Library e dichiararlo | §6.7 |

## 9. Quando rifare questa DPIA

- Si aggiunge un dato raccolto o mostrato, oppure si cambia il raggio, la regola del paywall o la conservazione.
- Si accendono i pagamenti reali o l'attestazione (aggiornare §2.3 righe 15-16, `store_privacy.md`, il registro).
- Si cambia l'hosting o si aggiunge un SDK di terzi.
- Dopo un incidente o un numero significativo di segnalazioni per stalking o molestie.

## 10. Parere e approvazione

| Ruolo | Nome | Data | Esito |
|---|---|---|---|
| Redattore tecnico | | 23/10/2026 | Bozza |
| Consulente legale / DPO | | | |
| Titolare | | | |
| Consultazione degli interessati (art. 35(9)), se fatta | | | |
| Consultazione preventiva del Garante (art. 36), se il rischio residuo resta alto | | | |
