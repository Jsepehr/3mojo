# Raen: risposte per App Store Connect e Google Play Console

> **Bozza tecnica, non consulenza legale.** Sono le risposte che proponiamo ai questionari privacy e di revisione degli store, motivate sul codice al commit `4f7cae1`. Le definizioni degli store cambiano: prima di inviare, rileggere le definizioni attuali sulle pagine ufficiali (App Store Connect → App Privacy; Play Console → Contenuti dell'app). In caso di dubbio abbiamo scelto la risposta **più prudente** (dichiarare di più), spiegando perché.
>
> Da tenere allineato con `ios/Runner/PrivacyInfo.xcprivacy` (aggiornato in questa revisione: tutti i tipi "collegati", più la cronologia acquisti) e con [informativa_bozza.md](informativa_bozza.md).

---

## A. Apple App Store Connect: "App Privacy"

**URL dell'informativa privacy**: obbligatorio, **[da pubblicare]**.
**Tracking** ("Do you or your third-party partners use data for tracking?"): **No**. Nessun SDK pubblicitario, nessun collegamento con dati di terzi, nessun broker. Nessun dominio di tracking nel privacy manifest.

**"Do you or your third-party partners collect data from this app?"**: **Yes**.

| Categoria → tipo | Raccolto? | Collegato all'identità? | Tracking? | Finalità | Motivazione |
|---|---|---|---|---|---|
| Location → **Precise Location** | Sì | **Sì** (prudente) | No | App Functionality | Inviata al server e tenuta in RAM per tutta la sessione, cioè oltre il tempo della singola richiesta: per Apple è "raccolta". Sul server sta nella stessa sessione del selfie (vedi sotto). La finalità comprende il controllo dei salti di posizione (sicurezza, che per Apple rientra in App Functionality) |
| Location → Coarse Location | No | | | | Non la raccogliamo separatamente. Dagli IP non ricaviamo la posizione |
| Sensitive Info → **Sensitive Info** | Sì | **Sì** | No | App Functionality | "Chi vuoi incontrare" più il genere = possibile orientamento sessuale |
| User Content → **Photos or Videos** | Sì | **Sì** (vedi la nota 1) | No | App Functionality | Selfie della sessione; conservato fino a 30 giorni in un record di moderazione se la sessione viene segnalata |
| User Content → **Emails or Text Messages** | Sì (prudente, vedi la nota 2) | **Sì** | No | App Functionality | Messaggi della chat, inoltrati dal server |
| User Content → Other User Content | No | | | | Proposte d'incontro e motivi di segnalazione sono codici di liste chiuse, non contenuti creati dall'utente |
| Purchases → **Purchase History** | Sì, **quando i pagamenti saranno reali** (vedi la nota 3) | **Sì** | No | App Functionality | Il server riceve la transazione e ne tiene un HMAC per 8 giorni |
| Identifiers → User ID | No | | | | Nessun account. Il segreto di sessione cambia a ogni Start. Il token di sblocco (casuale, 2 ore) è un attributo dell'acquisto, già coperto da Purchase History |
| Identifiers → Device ID | No | | | | Nessun IDFA o IDFV, nessun id salvato. App Attest (quando acceso) usa una **chiave nuova a ogni sessione** e il server non conserva `keyId` né la ricevuta: nessun identificativo stabile del dispositivo |
| Usage Data, Diagnostics | No | | | | Nessun SDK di analytics o crash. ML Kit (che invia telemetria) è solo su Android; su iOS il volto lo controlla Apple Vision, senza rete. I crash report che raccoglie Apple non vanno dichiarati |
| Contact Info, Health & Fitness, Financial Info, Contacts, Browsing/Search History, Other Data | No | | | | — |

**Nota 1: perché il selfie è "collegato", anche senza account.** La lettura ottimistica direbbe "non collegato": non esistono account né id fissi, e la sessione è usa e getta. Ma Apple considera collegato ciò che è riconducibile all'identità di una persona, salvo misure di de-identificazione **prima** della raccolta. Una foto nitida del volto è un identificativo diretto, e viene conservata fino a 30 giorni nel record di moderazione. Sul server posizione, profilo, messaggi inoltrati e token stanno nella stessa sessione del selfie: per coerenza sono tutti "collegati". **Raccomandazione: "Linked to you" per tutti.** È ciò che oggi dichiara il privacy manifest. L'etichetta che ne risulta ("Data Linked to You") è meno attraente, ma non contestabile.

**Nota 2: i messaggi.** Per Apple "raccogliere" vuol dire trasmettere fuori dal dispositivo in modo da potervi accedere oltre il tempo necessario a servire la richiesta in tempo reale. I messaggi sono inoltrati e mai conservati, quindi a rigore potrebbero **non** essere "raccolti". Li dichiariamo lo stesso: transitano dal nostro server, e la dichiarazione in eccesso non ha conseguenze.

**Nota 3: cronologia acquisti.** Oggi il pagamento è simulato e in release non disponibile senza `--dart-define=REAL_PAYMENTS=true`. Il codice del pagamento reale è però già nell'app: il manifest lo dichiara già, e App Store Connect va compilato con Purchase History dalla prima versione con pagamenti reali (o subito, per non dimenticarlo).

**Required reason API** (manifest): `NSPrivacyAccessedAPICategoryUserDefaults` con `CA92.1` (`shared_preferences`, solo dati dell'app). Prima dell'invio generare il **Privacy Report** dall'archivio Xcode (Organizer → archivio → Generate Privacy Report) e controllare che ogni plugin (`geolocator`, `image_picker`, `shared_preferences`, `flutter_secure_storage`, `wakelock_plus`, `package_info_plus`, `share_plus`, `permission_handler`, `in_app_purchase`) porti il suo manifest.

---

## B. Google Play: "Data safety"

**Domande generali**

| Domanda | Risposta | Motivazione |
|---|---|---|
| L'app raccoglie o condivide dati utente dei tipi richiesti? | Sì | |
| Tutti i dati sono cifrati in transito? | **Sì** | La release accetta solo `https://`/`wss://` (`lib/core/network/api_config.dart`). ML Kit e Play Integrity usano HTTPS |
| L'app consente di creare un account? | **No** | Quindi non serve il link web per la cancellazione dell'account |
| Fornite un modo per chiedere la cancellazione dei dati? | **Sì** | End cancella subito la sessione sul server; "Cancella profilo" lo cancella dal telefono (e da online chiude prima la sessione); i record di moderazione si possono far cancellare scrivendo al contatto di sicurezza (**da attivare**) |
| Revisione di sicurezza indipendente (MASA) | No (facoltativa) | |

**Tipi di dati.** "Condiviso" su Play vuol dire trasferito a **terzi**. Il trasferimento ad altri utenti avviato dall'utente stesso (andare online, mandare un messaggio) e quello a fornitori che trattano per nostro conto sono esenzioni previste da Google.

| Tipo (Play) | Raccolto | Condiviso | Effimero | Obbligatorio / facoltativo | Finalità | Note |
|---|---|---|---|---|---|---|
| Posizione → **Posizione precisa** | Sì | No | **No** | Obbligatorio | Funzionalità dell'app; Prevenzione di frodi, sicurezza e conformità | In RAM per tutta la sessione (non è "effimero" nel senso di Play). Mai inviata ad altri utenti. Controllo dei salti di posizione |
| Informazioni personali → **Orientamento sessuale** | Sì | No | No | **Facoltativo** (percorso neutro "Preferisco non dirlo" più "Tutti") | Funzionalità dell'app | "Chi vuoi incontrare" più il genere. Mai mostrato ad altri |
| Informazioni personali → **Altre informazioni** (genere) | Sì | No | No | Facoltativo ("Preferisco non dirlo") | Funzionalità dell'app | Mostrato ad altri solo se l'utente lo sceglie (esenzione per azione dell'utente) |
| Foto e video → **Foto** | Sì | No (vedi la nota) | **No** | Obbligatorio | Funzionalità dell'app; Prevenzione di frodi, sicurezza e conformità | Il selfie è mostrato alle persone vicine per scelta dell'utente (Start). Conservato fino a 30 giorni nel record di moderazione se la sessione viene segnalata |
| Messaggi → **Altri messaggi in-app** | Sì | No | **Sì** | Facoltativo | Funzionalità dell'app | Inoltrati in memoria, mai salvati sul server: rientra nella definizione Play di trattamento effimero |
| Attività nelle app → **Altre azioni** | Sì | No | No | Facoltativo | Funzionalità dell'app; Prevenzione di frodi, sicurezza e conformità | Richieste d'incontro, blocchi, segnalazioni (i motivi finiscono nel record di moderazione) |
| Informazioni finanziarie → **Cronologia acquisti** | Sì, **quando i pagamenti saranno reali** | No | No | Facoltativo | Funzionalità dell'app; Prevenzione di frodi | Google gestisce il pagamento; il server tiene un HMAC del `purchaseToken`/ordine per 8 giorni |
| ID dispositivo o altri ID | **Sì** | No (vedi la nota) | No | Obbligatorio | **Analisi** (diagnostica ML Kit); Prevenzione di frodi e sicurezza (Play Integrity, quando attiva) | **Raccolto dagli SDK di Google, non da noi**: ML Kit invia un identificativo per installazione; Play Integrity un certificato di attestazione della chiave e un token del dispositivo. Play chiede di dichiarare anche ciò che raccolgono gli SDK |
| Informazioni e prestazioni app → **Diagnostica** | **Sì** | No | No | Obbligatorio | Analisi | Telemetria ML Kit (latenza, configurazione, dimensioni, codici d'errore, modello del dispositivo, versione dell'app) |
| Nome, email, telefono, contatti, calendario, file, salute, audio, cronologia web, app installate | No | | | | | |

**Note e scelte contestabili**
- **Foto "condivise"?** Google esenta i trasferimenti che l'utente avvia sapendo che i dati saranno mostrati ad altri, come nelle app di messaggistica. **Raccomandazione: "No"**. Se un revisore contestasse, rispondere "Sì, funzionalità dell'app" è innocuo nei fatti, ma fa comparire nella scheda una "condivisione con terze parti" che non c'è.
- **Telemetria ML Kit "condivisa"?** Secondo la pagina di Google ("ML Kit Android data disclosure") ML Kit non trasferisce i dati a terzi e li usa per diagnostica e statistiche d'uso. La risposta proposta, "raccolto, non condiviso", segue quella guida. Se il consulente qualificasse Google come **titolare autonomo** di quella telemetria, la risposta prudente diventerebbe "condiviso". Decisione legata alla DPIA §8, punto 4. **Per eliminare il problema**: sostituire ML Kit con `android.media.FaceDetector` (on-device, senza rete).
- **Play Integrity** (solo con `ATTESTATION_MODE` `log` o `enforce`): Google dichiara la raccolta di dati dell'app (pacchetto, versione, certificato), dello stato di licenza Play e del dispositivo (certificato di attestazione della chiave, token del dispositivo) per verificare l'integrità, cifrati e cancellati dopo un periodo di conservazione fisso: **non** effimeri. Dichiararli dalla prima versione in cui l'attestazione può essere chiesta. Visto che la libreria è già nell'APK, è più semplice dichiararli subito.
- **IP**: Play non lo tratta come tipo a sé, salvo quando se ne ricava la posizione (non è il nostro caso).

---

## C. Posizione in background (Google Play)

**Stato verificato.** L'app **non** chiede `ACCESS_BACKGROUND_LOCATION`. Nel manifest ci sono `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS` e `WAKE_LOCK` (`android/app/src/main/AndroidManifest.xml`; nel manifest unito di release in `build/` il servizio `geolocator` è `foregroundServiceType="location"`). La posizione con l'app in background passa da un **foreground service** avviato quando l'app è in primo piano (Start), con una notifica persistente. Per Android questo è accesso "in primo piano", quindi:
- il **modulo "Autorizzazioni di accesso alla posizione"** (background location) di Play Console **non** dovrebbe servire. Va confermato sull'AAB finale: Play Console → Esplora app bundle → Autorizzazioni. Se qualche libreria aggiungesse `ACCESS_BACKGROUND_LOCATION`, il modulo diventerebbe obbligatorio (testo pronto sotto);
- serve invece la **dichiarazione dei servizi in primo piano** (Play Console → Contenuti dell'app → Autorizzazioni per i servizi in primo piano; obbligatoria per le app con target Android 14 o successivo): tipo `location`, descrizione, impatto se interrotto, link a un video.

**Dichiarazione del foreground service (tipo "Posizione")**

> *Descrizione (EN, da incollare)*: Raen shows people who are physically near each other at the same moment (within 100 m) so they can meet in person. When the user taps **Start** and goes online, the app starts a location foreground service, with a persistent notification "Raen is online — People near you can see you, even with the app in the background", so the user stays visible to people nearby and keeps seeing them if they lock the screen or switch apps for a moment. The service stops as soon as the user taps **End**. Location is sent only to our server, which never shares coordinates or distances with other users.
>
> *Impatto se differito o interrotto*: The user would disappear from the nearby list and stop seeing people nearby as soon as the screen locks, and an ongoing meeting request or match could be lost. The feature cannot be deferred: it only makes sense in real time, while the person is physically there.

**Copione del video** (30-60 s, registrato su un telefono reale; `FLAG_SECURE` rende nera la registrazione dello schermo, quindi va usata una build di test senza flag o va filmato il telefono da fuori):
1. App aperta offline: "Start" in evidenza.
2. Tap su Start, selfie, intento → richiesta del permesso di posizione **"Mentre usi l'app"** → concessa.
3. Richiesta del permesso per le notifiche (Android 13+) → concessa. Compare la notifica "Raen è online".
4. Lista "Vicinanze" (con un secondo telefono vicino, dopo un minuto fermi).
5. Tasto Home: la notifica resta. Aprire la tendina delle notifiche e mostrarla.
6. Riaprire l'app e premere **End**: la notifica sparisce.

**Informativa in evidenza (prominent disclosure).** **Oggi manca** (DPIA, D6). Va mostrata **prima** della richiesta del permesso di posizione, dentro l'app, staccata da informativa e termini, con un'azione esplicita per accettare. Testo proposto, da aggiungere agli ARB in tutte le lingue:

> **IT**: Quando premi Start, Raen usa la tua posizione precisa per mostrarti chi è entro 100 metri e per mostrare te a loro. **Su Android resti visibile anche con l'app in background o con lo schermo bloccato**, finché non premi End: te lo ricorda una notifica fissa. Non mostriamo mai a nessuno la tua posizione né la distanza da te. [Continua] [Non ora]
>
> **EN**: When you tap Start, Raen uses your precise location to show you people within 100 metres and to show you to them. **On Android you stay visible even when the app is in the background or the screen is locked**, until you tap End: a persistent notification reminds you. We never show anyone your location or how far you are. [Continue] [Not now]

**Se un giorno servisse il modulo "background location"** (`ACCESS_BACKGROUND_LOCATION`): funzionalità principale "Mostrare e rendere visibili in tempo reale le persone fisicamente vicine mentre l'utente è online (tra Start ed End)"; perché in background: "Per non sparire dalla lista appena lo schermo si blocca, durante un incontro in corso"; alternative valutate: il foreground service con la notifica (quello che si usa oggi). Nota: con quel permesso Play esige che la funzione sia **principale** e un video che mostri l'informativa in evidenza e la richiesta di runtime.

---

## D. Note per App Review (Apple) e revisione di Google

**Testo proposto per "Notes for review" (EN)**

> **No account needed.** Raen has no sign-up and no login: tap **Start**, take a selfie (front camera; the app checks on-device that there is a face), pick an intent, allow location "While Using the App", and you are online. Tap **End** (red, top right) to go offline: everything about the session is deleted from our server.
>
> **How to see other people.** Raen only shows people who are physically within 100 m, online at the same time, compatible both ways (gender / who they want to meet, set once in the profile) and who have **both stayed put for at least one minute**. With a single device the list will stay empty by design. To test: use two devices side by side, with compatible profiles (e.g. both "Everyone"), tap Start on both and wait about one minute without moving. You will then see each other, can send a meeting request (tap the photo → choose a proposal), accept it on the other device and chat. **[If available: a demo video is at <link>, and we can keep test sessions online near Apple Park during the review window — contact <email/phone>.]**
>
> **User-generated content and safety (Guideline 1.2).** Users must accept the Terms of Use (zero tolerance for objectionable content and abusive users) before going online. Content is limited: a selfie (front camera only, must contain a face), choices from closed lists (intent, languages, meeting proposals: no free text, no romantic or sexual options), and chat text that is only possible after **both** people accepted a meeting. Every person, request and match has a ⋯ menu with **Block** (immediate, both ways) and **Report** (closed list of reasons, including "Seems to be under 18"; reporting also blocks). Sessions reported by several people are closed automatically; each reported session creates an encrypted moderation record (photo, reasons, time) reviewed by our team, who act on reports within 24 hours. Contact: **[safety@…]**, shown in Menu → Safety & reports.
>
> **18+ only.** Users must confirm they are at least 18 to create a profile; the age rating is 18+.
>
> **In-app purchase.** One **consumable** product: it unlocks the photos of all nearby people for 2 hours, from the moment of purchase, and can be bought again. It is not a subscription: it doesn't renew, has no recurring billing and doesn't grant ongoing access to content. Like time-limited "boosts" in other apps, it is consumed when used. There is no "Restore Purchases" button because consumables cannot be restored (Guideline 3.1.1 asks for restore only for non-consumables and subscriptions). Since Raen has no accounts, a time-limited unlock tied to a restorable account (non-renewing subscription) would require an account, which the app deliberately avoids. The unlock is validated by our server with the App Store; sandbox purchases are accepted for review.
>
> **Privacy.** Location is used only while online and never shown to other users (no distances). Gender and "who you want to meet" require explicit consent and are never shown ("who you want to meet") or shown only if chosen (gender). Chats are relayed, never stored. The face check runs on-device (Apple Vision). No tracking, no ads, no analytics.

**Note operative per la revisione**
- **Rischio 2.1** (app che "non mostra niente" con un solo dispositivo): è il punto più probabile di rifiuto. Decidere prima dell'invio una delle due strade: (a) video più disponibilità a una prova dal vivo; (b) sessioni di prova reali tenute online vicino al luogo della revisione. **Non** usare profili finti in produzione visibili agli utenti veri.
- **Guideline 1.2 "filtraggio"**: non c'è un filtro automatico dei contenuti offensivi in foto e chat (solo il controllo del volto). Lo compensano liste chiuse, chat solo dopo un sì reciproco, blocco e segnalazione. Se Apple lo chiede, valutare un controllo on-device della nudità nel selfie (decisione di prodotto).
- **Guideline 1.1.4** (app di "hookup"): nessuna opzione romantica o sessuale, solo proposte neutre. Tenerlo così anche nelle schermate dello store.
- **Guideline 5.1.1(v)** (cancellazione dell'account): non si applica, non ci sono account.
- **Guideline 5.1.1(i)**: link all'informativa in App Store Connect **e** dentro l'app (oggi manca).
- **Attestazione**: se è in `enforce` durante la revisione, i dispositivi di Apple sono reali e App Attest funziona. Il simulatore no.
- **Google Play**: politica "Contenuti generati dagli utenti" (termini accettati, segnalazione e blocco in app, moderazione); dating app → pubblico di destinazione **solo 18+**; nessun annuncio; dichiarazione "L'app contiene annunci?" → No.

---

## E. Età e classificazione

| Store | Raccomandazione | Note |
|---|---|---|
| Apple | **18+** | Nel questionario dell'età di App Store Connect rispondere con sincerità: contenuti generati dagli utenti **sì**, messaggistica/chat tra utenti **sì**, nessun contenuto sessuale né violento. Se il calcolo automatico desse una fascia più bassa, scegliere comunque la classificazione più alta (18+) con l'apposita opzione: è un'app per incontrare sconosciuti di persona |
| Google Play (IARC) | Questionario IARC con elementi interattivi: **"Gli utenti interagiscono"**, **"Condivide la posizione"** (prudente: la vicinanza entro 100 m è rivelata agli altri), **"Acquisti digitali"** | La classificazione la decide IARC (PEGI, ESRB…), non noi. In **Pubblico di destinazione e contenuti** scegliere **solo 18 anni e oltre**: è questo che esclude i minori su Play, non il rating IARC |
| Entrambi | Testi e screenshot dello store senza promesse di incontri romantici né immagini allusive | Coerente con l'1.1.4 di Apple e con le politiche Play sui contenuti sessuali |
