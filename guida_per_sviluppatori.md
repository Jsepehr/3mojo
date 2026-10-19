# Guida per sviluppatori — 3mojo_app

Questa guida spiega **a livello di codice** come è fatta l'app, con l'obiettivo che chi la legge possa aggiungere o modificare una feature senza dover reverse-engineerare tutto da zero. Le regole architetturali "ufficiali" restano in [CLAUDE.md](CLAUDE.md) (cosa va dove) e [CHECKLIST.md](CHECKLIST.md) (le domande da farsi prima di creare un file) — questa guida le dà per lette e si concentra sul **come funziona davvero**, feature per feature, con nomi di classi e file reali.

Nomi: per l'utente l'app si chiama **Raen**; il repository e i pacchetti Dart si chiamano `threemojo_app` (app) e `threemojo_server` (server).

---

## 1. Due progetti, un repository

```
3mojo/
  lib/            ← app Flutter (client, multi-piattaforma: Android/iOS/web/desktop)
  server/         ← backend Dart Frog (server/), gira in locale, in memoria
  test/           ← test dell'app Flutter
```

Sono due pacchetti Dart **indipendenti**, ognuno con il proprio `pubspec.yaml`. Clonando il repo va fatto `pub get` in entrambi:

```
flutter pub get          # dalla root, per l'app
cd server && dart pub get  # per il server
```

Comunicano tramite un **unico WebSocket per sessione** (`GET /ws`, senza parametri nell'URL), non richieste HTTP separate: il client si autentica col primo messaggio, poi manda presenza/azioni sul canale aperto, e il server spinge indietro liste e aggiornamenti appena cambia qualcosa. Ci passano presenza/vicinanze, richieste d'incontro (`encounters/`) **e** i messaggi di chat — per la chat il server fa solo da postino (inoltra, non conserva, e solo tra due sessioni con un match attivo): la cronologia esiste solo in memoria sui due telefoni, mai su disco (vedi §3.4). Eccezione deliberata: `paywall/` (§3.6) usa due route HTTP semplici (`POST /paywall/purchase`, `POST /paywall/status`) — non serve il push in tempo reale per un controllo puntuale come "sono ancora sbloccato?".

**Fonte di verità del protocollo**: il commento in testa a [server/routes/ws.dart](server/routes/ws.dart) (tutti i messaggi e i campi). In sintesi:

- client → server: `hello` (segreto di sessione, obbligatorio e primo, entro 10 s), `presence` (posizione; profilo e selfie solo alla nascita della sessione), `sendEncounterRequest`, `respondToEncounterRequest`, `endMatch`, `chatMessage`, `ping` (ogni 20 s, e quando l'app torna in primo piano), `end` (End esplicito);
- server → client: `welcome` (`resumed`, `graceSeconds`), `nearby`, `encounters`, `chatMessage`, `pong` (risposta a ogni `ping`), `rejected` (un'azione rifiutata dalle regole, col motivo), `error` (`invalidSecret`/`rateLimited`, seguito dalla chiusura del socket).

Gli id delle altre persone nei payload (`personId`, `otherPersonId`, `fromPersonId`) sono **pseudonimi per osservatore**: la stessa persona ha un id diverso per ognuno che la vede, e il client rimanda indietro quello ricevuto.

---

## 2. Architettura del client (`lib/`)

Clean architecture a tre layer per ogni feature, con la freccia delle chiamate che scende sempre:

```
presentation  →  domain  ←  data
(UI, stato)      (regole)    (dati veri: rete/disco/memoria)
```

- **`domain/`** non importa mai nulla da `data/`. Se ti accorgi di doverlo fare, hai sbagliato direzione.
- **`data/`** implementa i contratti (`abstract class`) definiti in `domain/repositories/`.
- **`presentation/`** parla solo con `domain/` (use case), mai direttamente con `data/`.

### Struttura di una feature

```
lib/features/<nome>/
  data/
    datasources/   <nome>_remote_data_source.dart (+_impl, +_fake_impl)
                   <nome>_local_data_source.dart (+_impl)
    models/        <nome>_model.dart        (extends l'entity, ha fromJson/toJson)
    repositories/  <nome>_repository_impl.dart
  domain/
    entities/      <nome>.dart               (classe pura, Equatable)
    repositories/  <nome>_repository.dart    (solo abstract class)
    usecases/      <azione>_usecase.dart     (una classe = un'azione)
  presentation/
    pages/         ui_<nome>.dart   → classe UiXxx
    providers/     pro_<nome>.dart  → classe ProXxx (ChangeNotifier)
    widgets/       cmp_<nome>.dart  → classe CmpXxx
```

Fuori dalle feature, `lib/core/` tiene ciò che più feature condividono senza dipendere l'una dall'altra: `network/` (`RealtimeConnection`, `ApiConfig`), `unlock/` (`UnlockTokenStore`), `errors/`, `usecases/`, `theme/` (`AppTheme`, `RaenColors`), `utils/` (`PhotoBytesCache`), `widgets/` (i `Cmp*` condivisi, §3.5).

**Dipendenze tra feature a senso unico**: quando `session/` deve far fare qualcosa alle altre feature a End, non le importa — definisce il contratto `SessionTeardownUseCase` e le altre lo implementano (`StopBeingVisibleUseCase`, `ClearEncounterSessionStateUseCase`, `ClearChatSessionUseCase`, `DiscardSelfieFilesUseCase`), cablati in `app.dart` (§3.1). Allo stesso modo `UiHome` compone le feature della home passando callback (`CmpPaywalledNearbyList` non conosce `encounters/` né `session/`).

### Gestione errori — la catena che attraversa tutti i layer

```
data/datasource       lancia   Exception   (ServerException, CacheException, LocationDisabledException,
                                             SelfieRejectedException, RateLimitedException...
                                             core/errors/exceptions.dart)
        │
data/repository_impl  cattura  Exception  →  ritorna  Either<Failure, T>
                                             (Failure in core/errors/failures.dart)
        │
domain/usecase         riceve  Either<Failure, T>, non fa mai try/catch
        │
presentation/provider   chiama result.match((failure) => ..., (value) => ...)
        │
UI                      sceglie il testo tradotto dal TIPO di Failure
```

Regola pratica: se stai scrivendo `try`/`catch` in un file dentro `domain/` o `presentation/`, ti sei sbagliato — quello sta solo in `data/`.

I `Failure` che l'utente deve capire sono **tipizzati** (`ConnectionFailure`, `NotOnlineFailure`, `NoFaceInSelfieFailure`, `ProfileMissingFailure`, `TooManyStartsFailure`, `AlreadyRequestedFailure`...): il loro `message` è un dettaglio tecnico in inglese e **non va mai a schermo**. Provider ed eventi espongono il `Failure` (non una stringa) e la UI sceglie icona e testo dagli ARB in base al tipo: `SessionFailureTexts` ([session_failure_texts.dart](lib/features/session/presentation/session_failure_texts.dart)), `ProfileLabels` ([profile_labels.dart](lib/features/profile/presentation/profile_labels.dart)), `CmpNearbyErrorState`, `CmpEncounterNoticeListener`. Test: [test/features/failure_texts_test.dart](test/features/failure_texts_test.dart).

### Stato: Provider

Ogni feature ha un `ProXxx extends ChangeNotifier` che tiene lo stato di presentazione (liste, loading, errori) e chiama gli use case. Niente Riverpod/Bloc. I provider che parlano col server (`ProNearby`, `ProEncounters`, `ProChat`, `ProPaywall`) lavorano **solo da online**: ascoltano `WatchSessionUseCase` (lo stream Start/End della sessione) e a ogni Start si abbonano, a End si fermano e si azzerano — nessun timer che riprova a vuoto da offline.

### Dependency injection: `lib/app.dart`

Non c'è un framework DI: `App.build()` registra tutto a mano con `MultiProvider`, un `Provider`/`ChangeNotifierProvider` per classe, dal datasource fino al `ProXxx`. Per aggiungere una nuova feature, questo è il posto dove va cablata (vedi §6). Prima di costruire l'albero, `main.dart` esegue `WipeDataFromPreviousInstallUseCase` (§3.7) e legge la modalità finta (§3.5).

---

## 3. Le feature esistenti, una per una

### 3.1 `session/` — chi sei ora (nessun account permanente)

**Entity**: `OnlineSession` (`domain/entities/online_session.dart`) — `sessionId`, `selfieBytes` (il selfie **solo in memoria**, nessun percorso di file), `profile` (copia del `Profile` letto dal telefono allo Start, feature `profile/`) e `intent` (cosa cerchi in questa sessione, facoltativo). Nessun nome, nessuna email. Il `sessionId` (UUID v4 nuovo a ogni Start) è il **segreto** con cui il client si presenta al server nel messaggio `hello`: non esce mai dal telefono se non verso il server, e gli altri non lo vedono mai.

**Selfie** (`UiStartSession` → `ProSession` → use case → `SelfieRepository` → `SelfieLocalDataSourceImpl`):
- `TakeSelfieUseCase`: fotocamera frontale con `image_picker`, già ridotta a 1280 px; il file scritto dalla fotocamera viene letto in memoria e **cancellato subito**, insieme agli scatti rimasti nella stessa cartella. Da lì il selfie esiste solo come byte.
- `FlipSelfieUseCase`: molte fotocamere frontali Android salvano lo scatto speculare — decide l'utente col bottone sopra la foto. Ribalta in un isolate (`compute`) dopo aver applicato l'orientamento EXIF ai pixel, e toglie tutti i metadati.
- `DiscardSelfieFilesUseCase`: uno dei passi di End, ripulisce file rimasti (es. app chiusa a metà scatto).
- La preparazione per il server (640 px, EXIF tolto, JPEG qualità 80) è in `prepareSelfieForUpload` dentro `NearbyRemoteDataSourceImpl`; il server la ricontrolla comunque (§4).

**Flusso Start** (`UiStartSession` → `ProSession.start(params)`):
1. `StartSessionUseCase` valida che ci sia un selfie non vuoto (`SelfieMissingFailure`);
2. compone `GetProfileUseCase`: senza un profilo compilato fallisce (`ProfileMissingFailure`) — genere e "chi cerchi" servono al server per il matching;
3. compone `CheckSelfieHasFaceUseCase` (canale nativo `raen/face_detection`: Google ML Kit su Android in `FaceDetectionChannel.kt`, Apple Vision su iOS in `AppDelegate.swift` — **tutto on-device**, nessuna rete; il canale vuole un percorso, quindi i byte finiscono in un file temporaneo cancellato sempre a fine controllo) — se non c'è un volto, `NoFaceInSelfieFailure`; se il controllo non gira, `FaceCheckUnavailableFailure`. La pagina lo richiama anche subito dopo lo scatto, solo per un feedback immediato;
4. genera `sessionId` con `Uuid().v4()`;
5. `SessionRepositoryImpl.startSession` → `SessionLocalDataSourceImpl` — **una sola variabile in memoria** nel processo dell'app (niente `shared_preferences`, niente disco). Chiudere l'app azzera tutto: è voluto, "usa e getta".

**Start Session non chiama il server.** Il server scopre che esisti solo quando `ProNearby`, avvisato da `WatchSessionUseCase`, apre la connessione WebSocket (vedi 3.2).

**Flusso End** (`ProSession.end()` → `EndSessionUseCase`, costruito in `App._endSessionUseCase`):
1. la sessione locale si chiude **per prima**: chi sta ancora lavorando per lei (es. `WatchNearbyPeopleUseCase` in attesa del GPS) la ricontrolla dopo ogni attesa e non si ricollega più;
2. poi i passi `SessionTeardownUseCase` delle altre feature, **in parallelo e ognuno con un tempo massimo** (`EndSessionUseCase.defaultTeardownTimeout`, 3 s): `StopBeingVisibleUseCase` (manda `end` e chiude il socket, §3.2), `ClearEncounterSessionStateUseCase`, `ClearChatSessionUseCase`, `DiscardSelfieFilesUseCase`. Best-effort: se il server non risponde, l'uscita locale riesce lo stesso;
3. `ProSession` spegne il wakelock e svuota la cache delle immagini decodificate (`PaintingBinding.instance.imageCache`): foto altrui e proprio selfie non restano in RAM dopo End.

**Gotcha già capitato — il bottone End "non faceva niente"**: se il socket è in uno stato bloccato, `WebSocketChannel.sink.close()` può non risolversi mai; un `await` senza limite in un punto qualsiasi della catena (`StopBeingVisibleUseCase` → `NearbyRepository` → `NearbyRemoteDataSourceImpl` → `RealtimeConnection`) bloccava `end()` per sempre — la UI restava online senza nessun errore visibile. Oggi ci sono due limiti indipendenti: il timeout di ogni passo in `EndSessionUseCase` e quello di 2 s dentro `RealtimeConnection.disconnect()`. `ProSession` ignora anche il doppio tap (`isEnding`). Test di regressione in [test/features/session/pro_session_end_test.dart](test/features/session/pro_session_end_test.dart), con un `NearbyRepository` finto il cui `stopBeingVisible` non si risolve mai apposta.

`ProSession` accende/spegne anche `WakelockPlus` insieme a Start/End (online lo schermo non va in standby). Nei test, `WakelockPlus` va sostituito con un finto `WakelockPlusPlatformInterface` (assegnato a `wakelockPlusPlatformInstance`, `@visibleForTesting` in `package:wakelock_plus`), e il tempo si controlla con `fake_async` — non con `testWidgets()`, il cui orologio finto impedirebbe a un `Timer` reale come quello dietro `.timeout()` di scattare mai, a meno di avanzare il tempo a mano.

**Stato della connessione** (`ProConnection`, `WatchConnectionStatusUseCase`, `WatchServerSessionRestartsUseCase`, sopra `ConnectionRemoteDataSourceImpl`): `CmpConnectionBanner` mostra una striscia discreta "mi sto riconnettendo" sopra lista e chat senza svuotarle; `CmpConnectionNoticeListener` (in cima all'app) avvisa una volta quando il server ha **dimenticato** la sessione durante una caduta (un `welcome` con `resumed: false` che non è il primo della sessione) — lì `ProEncounters` azzera richieste e match. `ProConnection` osserva anche il ciclo di vita dell'app (`WidgetsBindingObserver`): a **resumed** chiama `CheckConnectionUseCase` → `ConnectionRepository.checkConnection` → `RealtimeConnection.checkAlive` (un `ping`; se il server non risponde entro 5 s il socket morto viene abbandonato e si riconnette subito). A **paused** volutamente non fa nulla: su Android il foreground service tiene viva la presenza in background, e su iOS il socket di un'app sospesa resta aperto lato server fino a `purgeStale` (90 s) — chiuderlo qui farebbe partire subito la grazia (45 s) e la sessione morirebbe prima.

**Cancellare il profilo da online** (`WithdrawProfileUseCase`, in `session/` perché compone `EndSessionUseCase`): prima si chiude la sessione — il server userebbe ancora genere e "chi cerchi" per il matching — poi `DeleteProfileUseCase`.

### 3.2 `nearby/` — chi c'è vicino

**Entity**: `NearbyPerson` — niente nome e **niente distanza**: `id` (pseudonimo valido solo su questo telefono), `photoBytes` (il selfie già decodificato, `null` se bloccato), `meetingChance` (`low`/`medium`/`high`, tre stadi discreti, mai una percentuale), `isLocked` (paywall, deciso dal server) e ciò che la persona ha scelto di mostrare dal profilo: `intent`, `languages`, `visibleGender` (`null` se non ha attivato "mostra il mio genere"). Chi cerca non arriva mai al client. La lista arriva già ordinata dal server, dalla persona più vicina.

**Due datasource**:
- `LocationLocalDataSourceImpl` → pacchetto `geolocator`, legge il vero GPS del telefono (permessi, servizio attivo, ecc.) sia una tantum (`getCurrentLocation`) sia in modo continuo (`watchPosition`, vedi sotto).
- `NearbyRemoteDataSourceImpl` → usa la connessione WebSocket condivisa (`RealtimeConnection`, sotto) verso il backend vero in `server/`. Base URL da `ApiConfig.wsBaseUrl` (`core/network/api_config.dart`, stesso host di `baseUrl` con schema `ws`/`wss`): `localhost` su web/desktop, `10.0.2.2` sull'emulatore Android, oppure `--dart-define=API_BASE_URL=http://<ip-lan>:8080` per un device fisico. In modalità finta al suo posto c'è `NearbyRemoteDataSourceFakeImpl` (§3.5).

**Flusso** (`ProNearby`, avviato da `WatchSessionUseCase` a ogni Start):

```
WatchNearbyPeopleUseCase.call()  (Stream, non Future)
  ├─ GetCurrentSessionUseCase        (chi sono — locale, se null: NotOnlineFailure)
  ├─ GetCurrentLocationUseCase       (GPS vero, una volta all'apertura)
  │    └─ ricontrolla che la sessione sia ancora la stessa (niente presenza "fantasma" dopo End)
  ├─ WatchPositionUseCase            (GPS vero, continuo → NearbyRepository.updatePosition)
  └─ NearbyRepository.watchNearbyPeople(...)
       └─ NearbyRemoteDataSourceImpl.connect(...)
            └─ RealtimeConnection.connect(sessionId)   → GET /ws, poi {"type":"hello","secret":...}
                 ├─ a ogni welcome: presenza completa (posizione + profilo + selfie* + unlockToken?)
                 ├─ poi solo posizione (+ unlockToken) a ogni lettura GPS
                 └─ ascolta {"type":"nearby","people":[...]} spinti dal server
```

La presenza "completa" riparte a **ogni** `welcome` (`RealtimeConnection.onReady`), quindi anche dopo una riconnessione: se la grazia era scaduta il server ha dimenticato tutto e la sessione riparte da lì. *Il selfie però non si rimanda con un `welcome` `resumed: true` se il server l'aveva già (si sa dalla prima lista `nearby` ricevuta dopo averlo mandato): lo fissa alla nascita della sessione e lo ignorerebbe. Il selfie si prepara sul telefono (`prepareSelfieForUpload`: raddrizzato, ridotto a 640 px, senza metadati); se la preparazione fallisce o resta oltre ~230 KB **non** si manda l'originale (il server chiuderebbe il socket a ogni riconnessione) ma nessuna presenza, con `SelfiePreparationException` → `SelfieNotUsableFailure`. Tre esiti riguardano lo Start stesso e diventano `Failure` che **restano** finché la sessione non cambia: `rejected` `invalidSelfie` → `SelfieRejectedByServerFailure` (da lì nessuna presenza parte più per quella sessione; la home propone di rifare lo Start), il selfie non preparabile → `SelfieNotUsableFailure` (stessa via d'uscita) ed `error` `rateLimited` → `TooManyStartsFailure`.

**Il raggio non esiste lato client**: `WatchNearbyPeopleUseCase` non lo conosce, `NearbyRepository`/`NearbyRepositoryImpl` non rifiltrano la lista in arrivo. L'unica autorità è il server — `ConnectionHub.radiusMeters` (100 m), più gli hotspot (sotto): una persona inclusa dal server solo grazie a un hotspot verrebbe scartata per errore da un filtro client che conoscesse solo il raggio base.

**Nessuna distanza al client**: il server la usa solo internamente (ordinamento, paywall) e non la manda — un numero preciso a ogni push, insieme a qualche spostamento, basterebbe a trilaterare la posizione di una persona. Per lo stesso motivo gli id sono pseudonimi per osservatore: due telefoni non possono confrontare le liste e riconoscere con certezza la stessa persona.

**Zone d'incontro (hotspot), rilevate dal server** (`HotspotStore`, [hotspot_store.dart](server/lib/src/hotspot_store.dart), documentato per il resto in §4): quando ≥3 sessioni sono reciprocamente entro 100m tra loro e sono già, ognuna per conto proprio, ferme da almeno 15 minuti, il loro centro diventa un hotspot per 1 ora — dentro **200m** da quel centro (240m per uscirne, isteresi contro l'oscillazione GPS), chi sta nello stesso hotspot si vede a vicenda anche oltre i 100m diretti (sempre col matching reciproco del profilo). L'utente non ne viene informato: i testi dell'app parlano solo dei 100 metri. Il client non sa nulla di hotspot, riceve solo una lista a volte più ampia di quanto il semplice raggio spiegherebbe.

**In attesa di una lista** (connessione in corso, o lista vuota): `CmpPaywalledNearbyList` mostra `CmpNearbyWaitingOverlay` ([cmp_nearby_waiting_overlay.dart](lib/features/nearby/presentation/widgets/cmp_nearby_waiting_overlay.dart)) — lo stesso radar animato della schermata Start (`CmpRadarBackground`, in `core/widgets/`), con sopra un velo che spiega a rotazione (ordine casuale, dissolvenza incrociata) le regole vere del server: raggio di 100 metri, permanenza minima, stadi di probabilità, niente profili permanenti, un incontro alla volta. Serve a far leggere l'attesa come comportamento intenzionale, non come un caricamento infinito. Gli errori a tutta pagina li disegna `CmpNearbyErrorState`, scelti dal tipo di `Failure` (offline, GPS spento, permesso negato, selfie rifiutato, troppi Start).

**Restare visibili con l'app in background (foreground service, solo Android)**: senza precauzioni Android congela il processo quando l'app va in background — timer fermi, socket aperti ma "muti". `LocationLocalDataSourceImpl.watchPosition()` — chiamato tramite `WatchPositionUseCase` da `WatchNearbyPeopleUseCase` — su Android usa `Geolocator.getPositionStream` con `AndroidSettings(foregroundNotificationConfig: ...)`: fa partire un vero **foreground service** nativo con una notifica persistente, che alza la priorità del processo. I testi della notifica vengono dagli ARB (`background_location_notification_*`): `UiHome` li passa a `ProNearby.setBackgroundLocationNotice` prima dello Start (entity `BackgroundLocationNotice`), perché il datasource GPS non ha un `BuildContext`. Sono **obbligatori** lungo tutta la catena (`WatchNearbyPeopleUseCase` → `WatchPositionUseCase` → `LocationRepository` → `LocationLocalDataSource`): il data layer non ha testi di riserva, e finché non arrivano `ProNearby` aspetta ad aprire l'ascolto. **Non è una garanzia assoluta** (non impedisce la chiusura se l'activity viene distrutta), ma copre il caso comune "ho premuto Home per un attimo". È lo stream del GPS stesso a scandire il ritmo (`intervalDuration: 60s`, `distanceFilter: 0`), non un timer Dart che si congelerebbe per primo.

Richiede quattro permessi in [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml): `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` (obbligatorio da Android 14), `POST_NOTIFICATIONS` (Android 13+) e `WAKE_LOCK` (obbligatorio perché `ForegroundNotificationConfig.enableWakeLock: true` — **gotcha già capitato**: senza questo permesso `geolocator` non lancia un errore visibile in Dart, ma una `SecurityException` nativa che fa fallire silenziosamente ogni `watchPosition()`: arriva solo la prima posizione, mandata da `getCurrentLocation()`, e poi più nessun aggiornamento).

Su Android 13+ dichiarare `POST_NOTIFICATIONS` nel manifest non basta: `watchPosition()` lo **richiede a runtime** con `package:permission_handler` (`Permission.notification.request()`) prima di aprire lo stream — best-effort: se l'utente nega, il tracking va avanti comunque, solo senza notifica visibile.

**Idea per il futuro, non ancora implementata**: dato che il foreground service tiene viva la connessione in background, una richiesta d'incontro in arrivo con l'app non in primo piano potrebbe mostrare una notifica locale (`flutter_local_notifications` o simile) — senza Firebase/APNs, perché il processo è già vivo e riceve il messaggio sul socket.

**Connessione condivisa: `RealtimeConnection`** ([core/network/realtime_connection.dart](lib/core/network/realtime_connection.dart)) possiede l'unico socket fisico per sessione, riusato da `nearby/`, `encounters/` e `chat/`: ognuno filtra dallo stream condiviso solo i messaggi del proprio `"type"`. Sta in `core/` perché nessuna feature debba dipendere da un'altra solo per condividere il canale.
- `connect(sessionId)` è idempotente: con la stessa sessione ritorna lo stesso stream (e, se si stava aspettando il prossimo tentativo, riprova subito — è il bottone "Riprova"); con una sessione diversa chiude prima quella vecchia.
- Il segreto viaggia solo nel messaggio `hello` dopo l'apertura, **mai nell'URL** (gli URL finiscono nei log di proxy e provider). `send()` funziona solo dopo il `welcome`, e ritorna `false` altrimenti: nessuna coda, i datasource lo traducono in `ServerException` → `ConnectionFailure` ("non inviato").
- `ping` applicativo ogni 20 s (il server chiude dopo 90 s di silenzio, e risponde `pong` a ogni `ping`); su mobile/desktop anche il ping WebSocket nativo (`realtime_socket_io.dart`), sul web no (`realtime_socket_web.dart`). `checkAlive()` (al ritorno in primo piano, vedi §3.1): se si stava aspettando il prossimo tentativo riprova subito, altrimenti `ping` e, se entro `probeTimeout` (5 s) non arriva nessun frame, abbandona il socket (chiuso senza `end`, così sul server parte la grazia) e si riconnette.
- **Riconnessione centralizzata qui**: se il socket cade, lo stream **non si chiude** — emette un errore (`ServerException`, che i repository traducono in `ConnectionFailure`) e intanto si riprova con backoff esponenziale e jitter da 0,5 a 30 s (`ReconnectBackoff`; dopo un rifiuto per troppi Start, codice 4008, si salta subito all'attesa massima). Entro i 45 s di grazia del server il `welcome` dice `resumed: true` e tutto riprende com'era. Lo stream si chiude solo con `disconnect()` (End, che manda prima `end` così il server chiude subito la sessione) o passando a un'altra sessione. Se End arriva **durante una riconnessione** (il socket non è pronto e non può portare `end`) ma si è ancora dentro la grazia annunciata dal server, `end` parte comunque su un socket "d'addio" a parte (`hello` → al `welcome` `end` → chiusura, un tentativo solo, al massimo 5 s, senza bloccare chi chiama): il partner vede finire il match subito invece che dopo 45 s. Senza rete il tentativo fallisce e resta la grazia del server, come prima.
- Il socket è dietro un'interfaccia sottile (`RealtimeSocket`, `realtime_socket.dart`) così i test usano un socket finto ([test/support/fake_realtime_socket.dart](test/support/fake_realtime_socket.dart)). **Gotcha da non ripetere**: il `Future ready` di un `WebSocketChannel` si completa con errore se la connessione fallisce; se nessuno lo legge Flutter lo segnala come "Unhandled Exception" anche se l'errore arriva comunque sullo stream — `RealtimeConnection` lo ascolta sempre con un `onError`.

**Cosa fa `ProNearby` con gli errori**: una caduta di rete non tocca la lista già mostrata (c'è `CmpConnectionBanner`); solo senza nessuna lista si mostra l'errore a tutta pagina con Riprova. L'unico caso in cui lo stream finisce da online è un problema di posizione (GPS spento, permesso negato): lì `ProNearby` riprova da sola dopo 3 s (`_locationRetryTimer`), così tornando dalle impostazioni la lista riparte senza toccare nulla.

Tap su una persona → non chiama `nearby/`: `UiHome` passa a `CmpPaywalledNearbyList` una callback che chiama `ProEncounters.sendRequest` (feature diversa, §3.3).

### 3.3 `encounters/` — richieste d'incontro

**Entity**: `EncounterRequest` (`id`, `otherPersonId` — lo stesso pseudonimo di "Vicinanze" —, `status`: `pending`/`accepted`/`declined`/`cancelled`/`ended`, più selfie e profilo visibile dell'altra persona solo finché la richiesta è `pending`/`accepted`) ed `EncounterRejection` (azione rifiutata dal server col motivo: `self`, `notOnline`, `notNearby`, `locked`, `alreadyRequested`, `inMatch`, `tooManyPending`, `other`).

`EncounterRemoteDataSourceImpl` usa la stessa `RealtimeConnection` di `nearby/` (nessun secondo socket): `watchRequests(sessionId)` filtra gli snapshot `"type":"encounters"`, `watchRejections(sessionId)` i `rejected`; `sendRequest`/`respondToRequest`/`endMatch` mandano un messaggio e basta — l'esito arriva col prossimo snapshot spinto dal server. Se il messaggio non parte (offline), lo use case ritorna `Left(ConnectionFailure)`.

**Regole di business — applicate dal server** (`EncounterStore` + `RealtimeMessageHandler`, l'unico posto che conosce le richieste di *entrambe* le parti):
- accettare una richiesta cancella automaticamente tutte le altre pendenti, in entrata e in uscita, **per entrambi** i partecipanti — un solo incontro attivo alla volta. `RespondToEncounterRequestUseCase` è un semplice passacarte;
- **una sola richiesta per coppia per tutta la sessione**, in qualsiasi direzione e stato (anche rifiutata: niente rimandare) → `alreadyRequested`. Il client applica la stessa regola prima di mandare: `HasRequestedPersonUseCase` (puro, sugli snapshot più le richieste appena partite) è usato da `SendEncounterRequestUseCase` (`AlreadyRequestedFailure`) e dalla UI (tile già "richiesta", non cliccabile);
- una richiesta parte solo verso chi è **in "Vicinanze" di chi chiede in quel momento** e non è bloccato dal paywall per lui, nessuno dei due già in un match, al massimo 5 pendenti in uscita e 20 in entrata;
- il rifiuto è visibile a chi ha chiesto (scelta deliberata: ci si potrebbe incontrare fisicamente).

Ogni rifiuto torna come `{"type":"rejected", ...}` e, tramite `WatchEncounterRejectionsUseCase`, diventa un evento di `ProEncounters` (`EncounterNotice`, concetto solo di UI in [encounter_notice.dart](lib/features/encounters/presentation/encounter_notice.dart)) che `CmpEncounterNoticeListener` racconta con una snackbar tradotta (così l'utente non crede partita una richiesta che il server ha scartato). Una richiesta partita ma **mai confermata** (né rifiutata) entro 10 s — il frame perso con un socket morto — è considerata persa (`FindLostEncounterRequestsUseCase`): la persona torna richiedibile e l'utente lo sa (`RequestNotConfirmedFailure`, testo `request_not_confirmed`). Gli snapshot `encounters` portano il selfie della controparte solo la prima volta per richiesta su ogni socket: `EncounterRemoteDataSourceImpl` tiene quello già ricevuto per id di richiesta.

`ProEncounters` si abbona allo stream di `WatchEncounterRequestsUseCase` (niente polling) ed espone `activeMatch`, la richiesta `accepted`. `CmpMatchGate` ([cmp_match_gate.dart](lib/features/encounters/presentation/widgets/cmp_match_gate.dart), montato in `app.dart` sopra `UiHome`) tiene la pagina del match **allineata** ad `activeMatch`: appena c'è un match spinge `UiActiveMatch` a schermo intero (con una vibrazione), quando il match non c'è più (chiuso dall'altra parte, sessione finita o ripartita sul server) chiude la pagina che aveva aperto, e alla chiusura chiama `ProChat.close`. "Un solo incontro alla volta" si ottiene così gratis dallo stack di `Navigator`. La pagina "Richieste" è `UiEncounters` (icona nella barra in basso della home online).

Selfie e profilo della controparte non sono mai conservati nella richiesta: il server li prende freschi da `SessionStore` a ogni snapshot, e per le richieste finite non li manda più.

**`EndMatchUseCase` compone `DeleteConversationUseCase`** (feature `chat`, cross-feature deliberato): terminare un match non deve lasciarsi dietro una chat orfana — vedi §3.4. Se il match finisce **non** per mano tua (l'altra persona lo chiude o va offline, o il server dimentica la sessione), lo decide `DetectEndedMatchUseCase` (riceve le richieste di prima e quelle nuove, ritorna l'evento `MatchEnd` col motivo) che compone `ForgetEndedMatchUseCase` e cancella la chat allo stesso modo; `ProEncounters` traduce solo l'evento in avviso. "Qual è il match attivo" è `FindActiveMatchUseCase`. `EncounterRemoteDataSourceFakeImpl` è la controparte finta, stateful, con le stesse regole: vedi §3.5.

### 3.4 `chat/` — conversazione reale (nessuna scadenza a tempo)

`ChatRemoteDataSourceImpl` tiene conversazioni e messaggi **solo in memoria** (mai `shared_preferences`, mai disco: chi prende in mano il telefono non deve poter leggere una chat finita, e chiusa l'app non ne resta traccia) e li scambia con la controparte sulla `RealtimeConnection` condivisa. `appendMessage` manda `{"type":"chatMessage","toPersonId":...,"text":...,"clientMessageId":...}` e **solo se è partito** lo aggiunge alla cronologia; altrimenti `ServerException` → `ConnectionFailure`. Un solo ascolto della connessione per sessione, aperto **all'inizio della sessione** (`ProChat` → `StartReceivingChatMessagesUseCase` → `ChatRemoteDataSource.startReceiving`), riceve ogni `chatMessage` (`fromPersonId`, `text`, `sentAt` con l'ora del server), lo aggiunge una volta sola e lo inoltra a chi ascolta quella conversazione: un messaggio arrivato prima che la pagina del match si apra è già in cronologia. `SendMessageUseCase` rifiuta un testo oltre 1000 unità UTF-16 (`MessageTooLongFailure`, lo stesso limite del server): il campo ha `maxLength` e, se con le emoji si sfora, il testo torna nel campo con una snackbar (`chat_message_too_long`) invece di diventare un "non inviato" che fallirebbe per sempre. `purgeLegacyChatStorage` ([chat_legacy_storage.dart](lib/features/chat/data/datasources/chat_legacy_storage.dart)), lanciata da entrambe le implementazioni (reale e finta) alla costruzione, cancella da `shared_preferences` le chat che le versioni vecchie dell'app salvavano su disco.

Il server (`RealtimeMessageHandler._handleChatMessage` → `ConnectionHub.relayChatMessage`) **fa solo da postino**: inoltra solo se tra i due c'è un match attivo (`EncounterStore.hasActiveMatch`) e il destinatario è connesso in questo momento, e non conserva nulla. Se non può consegnare risponde `rejected` (`notDelivered`, o `invalidText` per un testo vuoto o oltre 1000 unità UTF-16 — il socket resta aperto) con il `clientMessageId`: `WatchUndeliveredChatMessagesUseCase` lo fa arrivare a `ProChat`, che marca il messaggio come **non inviato** (`isUnsent`) — mai finto partito — e permette di rimandarlo (`resend`).

`ProChat` vive per tutta l'app ma lavora solo per il match aperto: si abbona a `WatchIncomingChatMessagesUseCase` per la conversazione aperta (una caduta di rete non chiude lo stream, nessun timer di riabbonamento) e `close()` — chiamato da `CmpMatchGate` quando la pagina del match si chiude, e da sé a fine sessione — ferma gli ascolti e svuota i messaggi.

**La cronologia non sopravvive alla fine del match** ("nessuna scadenza a tempo" in CLAUDE.md vuol dire solo che non c'è un timeout automatico): `deleteConversation(otherPersonId)` toglie conversazione e messaggi dalla memoria (chiamato da `EndMatchUseCase`/`ForgetEndedMatchUseCase`), e i messaggi tardivi di quella persona non ricreano la cronologia; `ClearChatSessionUseCase` (passo di End) dimentica tutto. `ChatRemoteDataSourceFakeImpl` (stessa interfaccia, nessuna rete, con un autoreply finto) è la controparte finta: vedi §3.5.

**UI in stile WhatsApp** (`CmpChatMessageBubble` e `UiActiveMatch`, solo presentation): fumetto con un angolo "a coda" e orario incorporato nel testo con un `WidgetSpan`; sfondo dell'area messaggi leggermente tinto (`Color.alphaBlend` col colore primario del tema, nessun asset preso da WhatsApp); barra di composizione a pillola con bottone invio circolare, e un bottone emoji (`emoji_picker_flutter`) che **sostituisce** la tastiera con un pannello a griglia: `_UiActiveMatchState` tiene un `FocusNode` dedicato al campo di testo per tornare da sola alla tastiera quando l'utente lo ritocca. Finché non c'è nessun messaggio, al posto della chat vuota c'è un'intestazione "È un incontro" con le due foto. Uscire (indietro o "Termina") chiede sempre conferma, perché termina il match per sempre.

### 3.5 `settings/` — lingua, tema, e l'interruttore finto/reale

**Entità**: `AppLanguage` (`system`/`english`/`italian`/`german`/`spanish`/`french`/`arabic` — `system` segue il telefono, le altre forzano una lingua) e `AppThemeMode` (`light`/`dark`, binario: in UI è una `SwitchListTile`). Entrambe **persistite** su `shared_preferences` (`SettingsLocalDataSourceImpl`) — a differenza della sessione online, lingua e tema devono sopravvivere alla chiusura dell'app.

`ProSettings` le carica all'avvio e le cambia dal cassetto laterale (`CmpAppDrawer`: profilo, lingua, tema, informazioni, condivisione). Il `MaterialApp` in [app.dart](lib/app.dart) osserva `proSettings.locale`/`proSettings.themeMode`.

**La modalità finta/reale** (`ProSettings.isFakeMode`) sceglie se l'app usa i datasource **reali** (richiedono `server/` acceso e raggiungibile) o quelli **finti** (`NearbyRemoteDataSourceFakeImpl`, `EncounterRemoteDataSourceFakeImpl`, `ChatRemoteDataSourceFakeImpl`, `PaywallRemoteDataSourceFakeImpl` — stessa interfaccia, nessuna rete). **Esiste solo nei build di debug**: `App.fakeModeAvailable = kDebugMode`; in release la voce del drawer non c'è e `GetFakeModeUseCase` risponde sempre `false`, anche se un valore salvato dice "finti" (`SetFakeModeUseCase` può sempre solo spegnerla). La scelta **non è effettiva subito**: `main.dart` legge il flag *prima* di costruire l'albero dei provider e lo passa ad `App(fakeMode: ...)`, che sceglie una volta per tutte quale implementazione registrare — cambiarla dal drawer richiede di riavviare l'app (il drawer lo dice con una snackbar). In modalità finta nessuno usa `RealtimeConnection`: lo stato di connessione resta `offline` e il banner non compare. Il finto di `nearby` simula 5 persone con un vero `arrivedAt` (quindi stadi coerenti col tempo, non col numero di aggiornamenti), applica la stessa regola del paywall e cambia id a ogni sessione, come gli pseudonimi; nessuna foto (segnaposto in UI).

**Widget condivisi** (`core/widgets/`, non specifici di nessuna feature): `CmpPhoto` (foto quadrata con angoli arrotondati, mai un cerchio), `CmpLoadingIndicator` (tre puntini animati al posto di `CircularProgressIndicator`), `CmpRadarBackground` (il radar della home offline e dell'attesa in "Vicinanze"), `CmpStatusMessage` (avviso a tutta area), `CmpInlineError`, `CmpStatusChip`, `CmpBusyFilledButton`, `CmpEndButton` (il bottone End rosso, uguale per sessione e match). Se aggiungi una feature con foto, stati di caricamento o avvisi, riusa questi invece di reintrodurre i widget Material grezzi. Le foto ricevute dal server sono decodificate una sola volta da `PhotoBytesCache` (`core/utils/`).

**Nota cosmetica**: i due `ColorScheme` di `AppTheme` ([core/theme/app_theme.dart](lib/core/theme/app_theme.dart)) sono scritti a mano, non generati con `ColorScheme.fromSeed` (che sposterebbe il blu del brand `#0236B3` verso un indaco spento): il tema scuro usa superfici blu navy. Il rosso del cuore è un accento raro in `RaenColors`, fuori dal `ColorScheme`.

### 3.6 `paywall/` — sblocco a pagamento (finto per ora)

**Regola di business — applicata solo dal server** (`_withPaywallVisibility` in [session_store.dart](server/lib/src/session_store.dart)): per chi non ha sbloccato, un terzo delle persone in "Vicinanze" resta visibile gratis — **le più lontane** — con un minimo di 2 (ma mai più di quante ce ne sono); le altre (le più vicine, quelle con probabilità d'incontro reale più alta) arrivano con `locked: true` e **senza selfie**: un client modificato non può leggerle, perché non gli arrivano mai. Il client non ricalcola nulla (prima duplicava la regola, con il rischio che i due calcoli divergessero): `GetLockedNearbyPeopleUseCase` ([get_locked_nearby_people_usecase.dart](lib/features/paywall/domain/usecases/get_locked_nearby_people_usecase.dart)) è una funzione pura che legge `NearbyPerson.isLocked` (nessuno bloccato se lo sblocco risulta attivo) e **riordina**: prima le persone gratis, poi le bloccate, mantenendo l'ordine del server dentro ciascun gruppo.

**Sblocco valido 2 ore, calcolate dal server — mai dal telefono** (`PaywallStore.unlockDuration`, [paywall_store.dart](server/lib/src/paywall_store.dart)): l'orologio del telefono è falsificabile, quello del server no. `PaywallStore` tiene in RAM `token → unlockedAt` (nessuna persistenza: riavvii il server e ogni sblocco sparisce). Il client usa due route HTTP (`PaywallRemoteDataSourceImpl`): `POST /paywall/purchase` risponde `{"unlockToken", "expiresInSeconds"}` (limitata per IP, §4), `POST /paywall/status` con `{"unlockToken"}` nel corpo risponde `{"isUnlocked"}` (POST e non GET: il token non deve finire negli URL, e quindi nei log).

**Token di sblocco, mai un id del dispositivo**: a ogni acquisto il server emette un token casuale valido 2 ore. Il telefono lo tiene in `UnlockTokenStore` ([core/unlock/unlock_token_store.dart](lib/core/unlock/unlock_token_store.dart)) **cifrato** con `flutter_secure_storage` (stesse opzioni del profilo) e **solo finché vale** — lo sblocco sopravvive a Start/End e alla chiusura dell'app, scaduto sparisce. Le versioni vecchie lo tenevano in chiaro in `shared_preferences` (insieme a un `deviceId` fisso): al primo accesso viene spostato e le vecchie chiavi cancellate **solo dopo che la scrittura cifrata è riuscita** (altrimenti restano e si riprova al prossimo avvio). Sta in `core/` perché lo usano due feature che non devono dipendere l'una dall'altra: `paywall/` lo salva e lo usa per chiedere lo stato (`PaywallLocalDataSourceImpl` delega a lui), `nearby/` lo manda con la presenza e ascolta `UnlockTokenStore.changes` per mandarlo subito dopo un acquisto a sessione già avviata. **Senza token non si contatta mai il paywall**: chi non paga non ha nessun identificativo, chi paga è riconoscibile solo per quelle 2 ore.

`ProPaywall` interroga il server **solo da online**: a ogni Start, poi ogni 5 minuti (`Timer.periodic`), così lo sblocco scade da solo in UI anche se l'app resta aperta oltre le 2 ore; a End il controllo si ferma.

**Nessuna dipendenza circolare con `nearby/`**: `paywall/` importa `NearbyPerson` da `nearby/domain/entities/` (lecito), ma `nearby/` non importa mai nulla da `paywall/`. La composizione (chi mostrare sfocato, il banner, la conferma d'acquisto) vive in `CmpPaywalledNearbyList` ([cmp_paywalled_nearby_list.dart](lib/features/paywall/presentation/widgets/cmp_paywalled_nearby_list.dart)), il corpo della home online, che usa i pezzi di `nearby/` (`ProNearby`, `CmpNearbyPersonTile`, `CmpNearbyWaitingOverlay`, `CmpNearbyErrorState`). `CmpNearbyPersonTile` ha un parametro generico `isLocked` (sfoca la foto, mostra un lucchetto) che non nomina "paywall".

**Pagamento finto**: `PurchaseUnlockUseCase` non fa nessun acquisto vero (e `POST /paywall/purchase` non verifica nessuna ricevuta) — Apple/Google richiedono i loro sistemi di in-app purchase, da registrare in App Store Connect/Play Console prima di poterli integrare con `package:in_app_purchase`. Quando ci sarà un prodotto reale, la vera chiamata va dentro `PurchaseUnlockUseCase` e il server dovrà emettere il token solo dopo aver verificato la ricevuta — il resto (provider, UI) non cambia.

### 3.7 `profile/` e privacy trasversale

**Profilo** (`Profile`: genere, chi vuoi incontrare, conferma 18+, consenso al dato sensibile, intento predefinito, max 2 lingue, "mostra il mio genere"): compilato una volta (`UiHome` mostra `UiProfile(isOnboarding: true)` finché manca) e modificabile dal drawer. `SaveProfileUseCase` contiene le regole (18+, almeno un genere cercabile, lingue supportate, consenso esplicito salvo il percorso neutro "preferisco non dirlo" + "tutti"), ognuna col suo `Failure`. Salvato **cifrato** da `ProfileLocalDataSourceImpl` (`flutter_secure_storage`: Keystore su Android con `allowBackup="false"`, Keychain `first_unlock_this_device` su iOS), mai in `shared_preferences` né sul server se non in RAM durante la sessione (`PresenceProfileModel` manda solo ciò che serve al matching: mai la conferma d'età né il consenso).

**Il Keychain iOS sopravvive alla disinstallazione**: per questo `main.dart`, prima di tutto, esegue `WipeDataFromPreviousInstallUseCase` — se manca il segno di installazione in `shared_preferences` (che invece sparisce con l'app), cancella tutto l'archivio cifrato rimasto da un'installazione precedente (`deleteAll`: profilo e token di sblocco), poi mette il segno. Se la cancellazione fallisce il segno non viene messo e si riprova al prossimo avvio.

**Protezioni di piattaforma**:
- Android: `FLAG_SECURE` su tutta l'app in `MainActivity.kt` (niente screenshot, registrazione o cast, anteprima nera nel multitasking) — su tutta l'app e non per schermata, perché quasi ogni pagina mostra selfie altrui o la chat;
- iOS: gli screenshot non si possono bloccare; `PrivacyCover` in `AppDelegate.swift` copre la finestra col blu del brand quando la scena va **in background** (`didEnterBackground`, prima dello snapshot del selettore delle app, che così non contiene selfie né chat) e la scopre a `willEnterForeground`/`didActivate` — non già a `willDeactivate`, che scatta anche dietro ai dialoghi di permesso (posizione, fotocamera) e li avrebbe fatti apparire su uno schermo blu pieno;
- in memoria: selfie solo come byte (§3.1), cache delle immagini svuotata a End, chat mai su disco (§3.4).

---

## 4. Il server (`server/`, Dart Frog)

Routing basato su file (convenzione Dart Frog): il path della cartella/file sotto `routes/` diventa l'URL. Variabili d'ambiente (`TLS_CERT_PATH`/`TLS_KEY_PATH`, `DEBUG_ENDPOINTS_TOKEN`, `TRUSTED_PROXY`) e riepilogo dei limiti: [server/README.md](server/README.md).

```
server/
  main.dart               ← entrypoint: HTTPS/WSS se ci sono TLS_CERT_PATH + TLS_KEY_PATH, altrimenti in chiaro
  routes/
    _middleware.dart      ← CORS, applicato a tutte le route
    index.dart            → GET /  (controllo di salute: {"service":"3mojo","status":"ok"})
    ws.dart               → GET /ws  (upgrade a WebSocket; protocollo documentato qui)
    debug/sessions.dart   → GET /debug/sessions   (spento di default, vedi sotto)
    paywall/purchase.dart → POST /paywall/purchase (limitata per IP)
    paywall/status.dart   → POST /paywall/status  ({"unlockToken"} nel corpo)
  lib/src/
    socket_session.dart   ← SocketSession: un socket dall'apertura alla chiusura (hello, limiti, end)
    session_lifecycle.dart ← SessionLifecycle: nascita, grazia di 45 s, fine (endNow), purge per silenzio
    realtime_message_handler.dart ← RealtimeMessageHandler: messaggi di un client autenticato, regole, `rejected`
    session_store.dart    ← SessionStore: Map<sessionId, Session> in RAM, nearbyPeople, paywall
    encounter_store.dart  ← EncounterStore: richieste d'incontro in RAM, esclusività
    paywall_store.dart    ← PaywallStore: Map<token, unlockedAt>
    hotspot_store.dart    ← HotspotStore: zone d'incontro in RAM
    connection_hub.dart   ← ConnectionHub: canali connessi, push di vicinanze/richieste/chat
    pseudonyms.dart       ← Pseudonyms: id per osservatore
    session_credentials.dart ← SessionCredentials: segreto del client → id interno casuale
    presence_profile.dart ← PresenceProfile: profilo della presenza, validato, matching reciproco
    selfie_validator.dart ← SelfieValidator: solo JPEG, ≤ 230 KB, metadati tolti
    new_session_rate_limiter.dart ← NewSessionRateLimiter: limite ai nuovi Start per IP
    rate_limiters.dart    ← SlidingWindowRateLimiter, purchaseRateLimiter, ConnectionRateLimiter
    client_ip.dart        ← IP del client vero dietro un proxy fidato (TRUSTED_PROXY)
    geo.dart              distanza Haversine tra due coordinate
    meeting_chance.dart   soglie di permanenza → low/medium/high
  tool/simulate_fake_devices.dart ← 20 dispositivi finti contro il server vero
```

Tutti gli store sono singleton in RAM (`Xxx.instance`) con un costruttore per i test: nessun database, riavvii il server e ogni sessione, richiesta e sblocco spariscono.

**`GET /ws`** ([routes/ws.dart](server/routes/ws.dart)) upgrada la richiesta a WebSocket con `shelf_web_socket` + `fromShelfHandler` (il ponte di Dart Frog verso un `shelf.Handler`, necessario perché solo la `shelf.Request` sottostante supporta l'hijack dell'upgrade), con ping WebSocket ogni 20 s; risolve l'IP del client (`resolveClientIp`) e affida il socket a una `SocketSession`. La route avvia anche (idempotenti) `SessionLifecycle.startAutoPurge` e `ConnectionHub.startHotspotDetection`.

**`SocketSession`** ([socket_session.dart](server/lib/src/socket_session.dart)):
1. **autenticazione col primo messaggio** `{"type":"hello","secret":...}` entro 10 s, altrimenti chiusura (4001) senza registrare nulla. `SessionLifecycle.hello` controlla il segreto (32–128 caratteri, altrimenti `error` `invalidSecret` + 4002): un segreto già legato a una sessione viva è una **riconnessione**, altrimenti è un nuovo Start e passa da `NewSessionRateLimiter` (20 per IP ogni 10 minuti, configurabile con `MAX_NEW_SESSIONS_PER_IP`; altrimenti `error` `rateLimited` + 4008). `SessionCredentials` traduce il segreto in un id interno casuale, che non esce mai dal server;
2. **limiti**: solo frame di testo (4003), dimensione massima per tipo (`RealtimeMessageHandler.maxCharsFor`: 320 KB per `presence`, 16 KB per `chatMessage` — soglia di sicurezza, il testo oltre 1000 unità UTF-16 torna `rejected` `invalidText` senza chiudere — 1 KB per il resto; oltre, 4009), un token bucket per connessione (`ConnectionRateLimiter`, 20 di fila poi 5 al secondo: oltre si scarta, dopo 50 scarti di fila chiusura 4029);
3. **fine**: `end` chiude la sessione subito; ogni altra chiusura avvia il periodo di grazia.

Nessuna eccezione esce da `SocketSession`: un messaggio malformato di un client non deve far cadere il server per tutti.

**`SessionLifecycle`** ([session_lifecycle.dart](server/lib/src/session_lifecycle.dart)) è l'unico punto in cui una sessione nasce, sopravvive a una caduta e finisce:
- `attach` (dopo ogni hello valido): registra il canale in `ConnectionHub` (un solo socket vivo per sessione: un eventuale vecchio viene chiuso con 4011), rende di nuovo visibile la sessione, manda `welcome` (`resumed`, `graceSeconds`), lo snapshot delle richieste e una lista vicinanze fresca;
- `detach` senza `end`: la sessione resta **intatta ma nascosta** da "Vicinanze" (`Session.connected = false`) per `gracePeriod` (**45 s**); riconnettersi con lo stesso segreto la riprende con lo stesso id, permanenza, richieste e match;
- `endNow` (End, grazia scaduta, purge): toglie la sessione da `SessionStore`, dimentica credenziale e pseudonimi, cancella le richieste pendenti, chiude il match attivo (`accepted` → `ended`) avvisando subito i partner, poi toglie da `EncounterStore` tutte le richieste della sessione;
- `purgeStale` ogni 30 s: termina (chiudendo il socket con 4010) chi non manda **nessun messaggio** da più di 90 s — il client manda un `ping` ogni 20 s, quindi una sessione viva non ci finisce mai.

**`RealtimeMessageHandler`** ([realtime_message_handler.dart](server/lib/src/realtime_message_handler.dart)) interpreta i messaggi di un client già autenticato e controlla ogni campo prima di toccare uno store. Ritraduce gli pseudonimi ricevuti (`toPersonId`) negli id interni con `Pseudonyms.resolve` — uno pseudonimo che quel client non ha mai ricevuto non si risolve. Ogni rifiuto che l'utente deve conoscere torna come `{"type":"rejected","action":...,"reason":...}`:
- `presence` → `SessionStore.upsertPosition(...)`, poi `ConnectionHub.broadcastNearbyUpdates()`. Profilo (`PresenceProfile.fromJson`, valori fuori dalle liste chiuse diventano neutri) e selfie (`SelfieValidator.sanitizeBase64`) contano **solo alla nascita della sessione**: fissarli impedisce di sondare la preferenza altrui cambiando il proprio genere a sessione aperta. Rifiuti: `invalidCoordinates`, `implausibleMovement` (salto oltre 50 m/s × tempo + 250 m di tolleranza, contro chi "teletrasporta" la posizione per sondare), `invalidSelfie`;
- `sendEncounterRequest` → le regole di §3.3, poi `pushEncounterSnapshot` per entrambi; `respondToEncounterRequest` (solo il destinatario, solo se pendente) → `pushEncounterSnapshot` per ogni sessione toccata, comprese quelle le cui richieste sono state cancellate dall'esclusività; `endMatch` (solo uno dei due partecipanti);
- `chatMessage` → `ConnectionHub.relayChatMessage`, oppure `rejected` `notDelivered`/`invalidText` (§3.4).

**`ConnectionHub`** ([connection_hub.dart](server/lib/src/connection_hub.dart)) tiene solo il lato di scrittura (`StreamSink`) di ogni sessione connessa — così è testabile con un semplice `StreamController` — ed è il punto in cui gli id interni diventano **pseudonimi per osservatore** (`Pseudonyms`, casuali, stabili per tutta la vita della coppia e dimenticati quando una delle due sessioni finisce). `broadcastNearbyUpdates()` richiama `SessionStore.nearbyPeople(...)` per ognuno e manda `{"type":"nearby","people":[...]}` solo a chi vede qualcosa di diverso dall'ultima volta (firma del payload: senza distanze le liste cambiano di rado, e ognuna porta i selfie). Ha un **throttle** di 500 ms (`broadcastThrottleInterval`, leading + trailing): la posizione si scrive sempre subito, solo il ricalcolo-e-invio è al più uno per finestra.

**`SessionStore.nearbyPeople`** ([session_store.dart](server/lib/src/session_store.dart)) applica, nell'ordine: solo sessioni connesse (non in grazia), matching **reciproco** sul profilo (`PresenceProfile.mutuallyCompatible`: ci si vede solo se ognuno rientra in ciò che cerca l'altro), distanza Haversine (`geo.dart`) entro **100 m** (`ConnectionHub.radiusMeters`) o stesso hotspot, permanenza minima 1 minuto, `meetingChance` da `meeting_chance.dart` (1/3/5 minuti), ordinamento dalla più vicina e infine il paywall (§3.6). Il client non riceve **mai** lat/lng né distanze, solo pseudonimo + stadio + `locked` + selfie (se non bloccato) + intento/lingue/genere visibile. Per non scandire tutte le sessioni online, i candidati vengono da un indice per fasce di latitudine di 100 m; i controlli esatti restano gli stessi. **Il raggio vive solo qui**: se lo cambi, aggiorna anche i testi dell'app che citano i 100 metri (`lib/l10n/*.arb`) e il commento di `PresenceProfile.mutuallyCompatible`.

**Stazionarietà anti-rumore GPS**: `Session` tiene due posizioni — `lat`/`lng` (l'ultima nota, per le distanze) e `anchorLat`/`anchorLng` (l'ancora per il dwell). `upsertPosition` sposta l'ancora — e quindi resetta `arrivedAt` — solo dopo **`confirmMovementReadings` (2) letture consecutive** oltre `stationarityRadiusMeters` (**60 m**): il GPS di uno smartphone ha già 5-20 m di errore tipico (anche 30-50 m al chiuso), e con una soglia più bassa senza debounce una sola lettura rumorosa faceva sparire per un altro minuto chi non si era mai mosso.

**`HotspotStore`** ([hotspot_store.dart](server/lib/src/hotspot_store.dart)) rileva zone d'incontro e allarga lì la visibilità reciproca — vedi §3.2 per il comportamento visto dal client. `nearbyPeople` accetta una coppia oltre il raggio base solo se `HotspotStore.sharesAnyActiveHotspot(...)` è vera (**stesso** hotspot per entrambi).

Regola di formazione: ≥`minClusterSize` (3) sessioni reciprocamente entro `clusterRadiusMeters` (100 m, tutte le coppie) e ognuna già ferma da ≥`clusterMinDwellMinutes` (15 min, riusa `Session.arrivedAt` — niente timer di gruppo né identità da tracciare); vive `lifetime` (1 ora). **Più alta della soglia di `MeetingChance.high`** (5 min) apposta: un falso positivo qui allarga la visibilità per un intero gruppo, e 5 minuti sarebbero bastati a 3 sconosciuti fermi allo stesso semaforo.

**Rinnovo, non ricreazione** — con lo **stesso vincolo della formazione**: a ogni giro, per ogni hotspot esistente, i "supporter" sono le sessioni idonee entro `Hotspot.radiusMeters` (200 m) che sono **anche** reciprocamente entro 100 m tra loro (bug corretto: la prima versione rinnovava con ≥3 sessioni qualsiasi entro 200 m, tenendo in vita hotspot che non avrebbero mai potuto formarsi). Se i supporter sono ≥3 l'hotspot si rinnova; se il gruppo è ridotto esattamente al minimo e nessun supporter è più vicino al centro originale, il centro viene **ricalcolato** sul loro centroide; sotto 3 l'hotspot scade da solo.

Il rilevamento **ignora genere/preferenza** (un fatto fisico, non una preferenza): il matching reciproco si applica dopo, coppia per coppia. Più hotspot possono esistere insieme, **mai due il cui cerchio si sovrappone** (`_wouldOverlapAnotherHotspot`: centro-a-centro ≥ 400 m), controllato sia alla creazione sia al ricalcolo del centro.

**Due ottimizzazioni sul peso di calcolo**:
1. **Partizionamento per fascia di latitudine**: la ricerca di nuove triple gira per fasce larghe `clusterRadiusMeters` — due sessioni in fasce non adiacenti sono per forza oltre 100 m — cercando in (fascia-1, fascia, fascia+1); i doppioni sono impediti da `_wouldOverlapAnotherHotspot`. Scala con la densità locale, non col totale delle sessioni online.
2. **Rilevamento su un timer proprio** (`ConnectionHub.startHotspotDetection`, ogni 15 s), non a ogni presenza: un hotspot si forma in 15 minuti e vive un'ora, qualche secondo di ritardo nella *scoperta* non conta. `broadcastNearbyUpdates` resta istantaneo e usa lo stato hotspot già noto. Un errore nel rilevamento non esce mai dal timer (farebbe cadere il processo).

**`EncounterStore`** ([encounter_store.dart](server/lib/src/encounter_store.dart)) tiene le richieste in RAM per `requestId`. `sendRequest` applica le regole che dipendono solo dalle richieste (lancia `EncounterRejected` con un `EncounterRejectionReason`); `respondToRequest(accepted: true)` cancella atomicamente ogni altra richiesta pendente che coinvolga **l'uno o l'altro** partecipante e ritorna anche quelle cancellate, così chi chiama sa chi altro notificare. Le richieste di una sessione (anche finite) restano finché la sessione vive — servono a vietare di rimandare — e vengono tolte del tutto alla fine (`forgetSession`). Selfie e profilo della controparte li aggiunge `ConnectionHub.pushEncounterSnapshot` da `SessionStore` a ogni snapshot, solo per richieste non finite e mai con "chi cerca".

**Altre protezioni**:
- `SelfieValidator` accetta solo un JPEG vero (marcatori SOI/EOI), al massimo ~230 KB, e toglie i segmenti di metadati (EXIF/XMP con la posizione dello scatto, IPTC, commenti, segmenti proprietari) prima di ridistribuirlo. Non decodifica i pixel: nessun dato biometrico lato server.
- `POST /paywall/purchase` è limitata per IP (`purchaseRateLimiter`, 10 ogni 10 minuti): ogni chiamata crea un token in memoria.
- I limiti per IP leggono `X-Forwarded-For` solo se la connessione arriva da un proxy elencato in `TRUSTED_PROXY` (`client_ip.dart`).

**`GET /debug/sessions`** → `debugSnapshot()`: per ogni sessione in memoria solo id interno, `connected`, `dwellSeconds`, `lastSeenSecondsAgo` — niente posizioni, distanze, selfie, genere né preferenza (con le distanze a coppie chiunque avesse il token potrebbe triangolare tutti). **Spento di default**: risponde solo se il server è avviato con `DEBUG_ENDPOINTS_TOKEN` e la richiesta manda lo stesso valore nell'header `X-Debug-Token` (confronto a tempo costante); altrimenti 404, come se non esistesse.

**Provare hotspot/vicinanze senza dispositivi reali** ([tool/simulate_fake_devices.dart](server/tool/simulate_fake_devices.dart), `dart run tool/simulate_fake_devices.dart [wsBaseUrl]` col server già acceso): apre 20 vere connessioni WebSocket con lo stesso protocollo dell'app (`hello`, `presence` ogni 20 s, `end` alla chiusura), ognuna con una posizione finta. Disposizione: due gruppi da 4+1 (i 4 si vedono subito con la regola normale; il quinto è oltre i 100 m dal nucleo ma dentro i 200 m dell'hotspot — è quello da guardare dopo 15 minuti), più 5 coppie isolate per la sola visibilità a due. Stampa la lista di ogni dispositivo solo quando cambia composizione. Attenzione: 20 connessioni dallo stesso IP sono esattamente il tetto predefinito di `NewSessionRateLimiter` (20 nuovi Start ogni 10 minuti): rilanciarlo subito dopo può essere rifiutato con `rateLimited`, e il simulatore lo ricorda all'avvio. Per le prove avvia il server con `MAX_NEW_SESSIONS_PER_IP=200`.

---

## 5. Come si fa girare in locale

```
# Server (dalla cartella server/)
dart pub get
dart pub global activate dart_frog_cli        # una tantum
dart pub global run dart_frog_cli:dart_frog build
dart build/bin/server.dart                     # ascolta su tutte le interfacce, porta 8080 (env PORT)
```

`dart_frog dev` (il comando "ufficiale" con hot reload) **non funziona in un terminale non interattivo** (es. lanciato da script/CI/agenti): prova a leggere da stdin e va in crash con `StdinException`. La build di produzione (`dart_frog build` + `dart build/bin/server.dart`) non ha questo problema; in un terminale normale invece `dart_frog dev` va benissimo.

```
# App (dalla root), device fisico sulla stessa Wi-Fi del PC
flutter run -d <device-id> --dart-define=API_BASE_URL=http://<ip-lan-del-pc>:8080
```

In release **e in profile** `API_BASE_URL` è obbligatorio e deve essere `https://` (`ApiConfig`, [api_config.dart](lib/core/network/api_config.dart)): selfie, posizione e profilo non devono mai viaggiare in chiaro. Il server parla TLS da sé con `TLS_CERT_PATH` + `TLS_KEY_PATH`, oppure va messo dietro un reverse proxy che termina TLS (vedi [server/README.md](server/README.md)). L'IP LAN del PC si trova con `ipconfig` (Windows) o `ipconfig getifaddr en0` (macOS); il firewall deve permettere connessioni in entrata sulla porta scelta.

**Se dimentichi `--dart-define=API_BASE_URL=...` su un device fisico**: `ApiConfig.baseUrl` cade sul default per Android (`10.0.2.2`, valido solo per l'emulatore) e la connessione va in timeout — si vede in `adb logcat` come `WebSocketChannelException: SocketException: Connection timed out ..., address = 10.0.2.2`. Prima di dare la colpa al codice, controlla sempre questo.

**Gotcha da ambiente incontrati e relative soluzioni**, se ricompaiono:
- `org.gradle.java.home` in `android/gradle.properties` oggi punta a `C:\Users\sepehrbaradaran\.jdks\azul-17.0.16` (un PC Windows), e i percorsi JDK/Flutter SDK in `.vscode/settings.json` sono anch'essi assoluti — validi solo sulla macchina su cui sono stati scritti. Altrove si rompe con `Java home supplied is invalid` o l'estensione Dart non trova l'SDK. **[macchine_sviluppo.md](macchine_sviluppo.md)** tiene una tabella dei percorsi già scoperti per macchina — guardala prima di rimetterti a cercare `where flutter`/cartelle `.jdks` da zero, e aggiungici una riga se scopri i percorsi di una macchina nuova.
- Cache di build Gradle/Kotlin corrotta dopo un'interruzione a metà (`already exists, it cannot be overwritten`, `Storage ... is already registered`) → `flutter clean` + `cd android && ./gradlew --stop` (ferma sia il Gradle Daemon che il Kotlin Compile Daemon rimasti vivi con cache stantie).

---

## 6. Come aggiungere una feature da zero

1. Copia la struttura di `lib/features/nearby/` (l'esempio più completo: datasource remoto+locale, reale+finto, entity+model separati, use case che ne compone altri) e rinomina cartelle/file/classi secondo le convenzioni in tabella (§2).
2. Parti dall'**entity** in `domain/entities/`: solo i dati che servono a una regola di business per decidere qualcosa. Un dettaglio tecnico o solo-da-mostrare resta sul **model** (`data/models/`), l'entity non lo vede.
3. Definisci il contratto in `domain/repositories/` (solo `abstract class`), poi lo **use case** in `domain/usecases/` che lo chiama — è lì che vive ogni regola di validazione/business, mai nel provider né nel repository. Ogni errore che l'utente deve capire ha il suo `Failure` tipizzato.
4. Implementa `data/datasources/` (`Impl` in file separato dall'interfaccia, `FakeImpl` se serve la modalità finta) e `data/repositories/*_repository_impl.dart`: qui e solo qui si intercettano `Exception` tecniche e si ritorna `Either<Failure, T>`. Se la feature parla col server, usa `RealtimeConnection` (un nuovo `"type"` sullo stesso socket) e aggiorna il protocollo in `server/routes/ws.dart`.
5. Presentation: `ProXxx extends ChangeNotifier` che chiama gli use case (se lavora solo da online, ascolta `WatchSessionUseCase`), poi `UiXxx`/`CmpXxx` che osservano `ProXxx` con `context.watch`/`context.read`. Se a End deve dimenticare qualcosa, implementa un `SessionTeardownUseCase` e aggiungilo in `App._endSessionUseCase`.
6. Cablaggio in [lib/app.dart](lib/app.dart): un `Provider`/`ChangeNotifierProvider` per ogni classe nuova, nello stesso ordine di dipendenza (datasource → repository → usecase dentro il provider → ChangeNotifierProvider).
7. Testo utente: mai hardcoded — parti da `lib/l10n/app_en.arb` (template, sempre aggiornato per primo), poi replica la stessa chiave in **tutte** le altre lingue (`app_it.arb`, `app_de.arb`, `app_es.arb`, `app_fr.arb`, `app_ar.arb` — le sei lingue forzabili di `AppLanguage`, più `system` che segue il telefono, vedi §3.5), infine `flutter gen-l10n` (output in `lib/l10n/generated/`). Dimenticare una lingua non rompe la build (va in fallback sul template), ma la lascia a metà tradotta.
8. Prima di scrivere, ripassa [CHECKLIST.md](CHECKLIST.md): la domanda "cosa sto descrivendo?" toglie quasi tutti i dubbi su dove va un file nuovo.

## 7. Come modificare una feature esistente — esempio pratico

Vuoi aggiungere un nuovo filtro a "Vicinanze" (es. distanza massima configurabile dall'utente invece che fissa a 100m)?

- Oggi il raggio esiste **solo sul server** (`ConnectionHub.radiusMeters`, passato a `SessionStore.nearbyPeople(radiusMeters: ...)` sia per la lista sia per il controllo di `sendEncounterRequest`): il client non ha nessuna costante né parametro di raggio, e non rifiltra la lista.
- Lato client la scelta dell'utente diventerebbe un parametro di `WatchNearbyPeopleUseCase.call(...)`, con la validazione (es. non oltre un massimo ragionevole) proprio lì, non nel provider; da lì scende fino a `NearbyRemoteDataSourceImpl`, che la manda al server (es. un nuovo campo della presenza).
- Il server resta l'autorità: `RealtimeMessageHandler` deve rivalidare il valore su un limite proprio (mai fidarsi del client) e `nearbyPeople` usarlo al posto della costante — tenendo conto che gli hotspot allargano comunque la visibilità oltre il raggio base. Documenta il nuovo campo nel commento di `routes/ws.dart`.
- Aggiorna i testi che citano i 100 metri (`lib/l10n/*.arb`).
- `ProNearby` non cambia: continua ad abbonarsi allo stream di `WatchNearbyPeopleUseCase` — ma non deve mai contenere la logica del filtro.

---

## 8. Test

```
flutter test                 # app: test/core/** e test/features/**
cd server && dart test       # server: server/test/**
```

App: i fake condivisi stanno in `test/support/` (`fake_repositories.dart`, `fake_realtime_socket.dart` per provare `RealtimeConnection` senza rete, `build_providers.dart`); per i timer si usa `fake_async`.

Server: `mocktail` per i finti `RequestContext` di Dart Frog dove serve (`test/routes/index_test.dart`, `test/routes/paywall/status_test.dart`). La route `/ws` fa hijack del socket e non è testabile con un `RequestContext` finto, ma tutta la sua logica sta in `SocketSession`, provata con due `StreamController` al posto del socket (`test/src/socket_session_test.dart`). Gli store hanno costruttori per i test con orologio controllabile o istanze indipendenti dai singleton — `SessionStore.withClock(...)`, `HotspotStore.withClock(...)`, `PaywallStore.withClock(...)`, `NewSessionRateLimiter.withClock(...)`, `EncounterStore.empty()`, `SessionCredentials.empty()`, `ConnectionHub.withStore(...)` — altrimenti i test si "sporcherebbero" a vicenda, dato che non c'è modo di resettare un singleton tra un test e l'altro.
