# Guida per sviluppatori — 3mojo_app

Questa guida spiega **a livello di codice** come è fatta l'app, con l'obiettivo che chi la legge possa aggiungere o modificare una feature senza dover reverse-engineerare tutto da zero. Le regole architetturali "ufficiali" restano in [CLAUDE.md](CLAUDE.md) (cosa va dove) e [CHECKLIST.md](CHECKLIST.md) (le domande da farsi prima di creare un file) — questa guida le dà per lette e si concentra sul **come funziona davvero**, feature per feature, con nomi di classi e file reali.

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

Comunicano tramite un **unico WebSocket per sessione** (`GET /ws`), non richieste HTTP separate: il client manda presenza/azioni sul canale aperto, il server spinge indietro liste e aggiornamenti appena cambia qualcosa, invece che il client debba richiederli a intervalli. Ci passano sia presenza/vicinanze sia le richieste d'incontro (`encounters/`). **Solo la chat resta locale** — non tocca mai il server (vedi §3.4).

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
    datasources/   <nome>_remote_data_source.dart (+_impl)
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

### Gestione errori — la catena che attraversa tutti i layer

```
data/datasource       lancia   Exception   (ServerException, CacheException, ...
                                             core/errors/exceptions.dart)
        │
data/repository_impl  cattura  Exception  →  ritorna  Either<Failure, T>
                                             (Failure in core/errors/failures.dart)
        │
domain/usecase         riceve  Either<Failure, T>, non fa mai try/catch
        │
presentation/provider   chiama result.match((failure) => ..., (value) => ...)
```

Regola pratica: se stai scrivendo `try`/`catch` in un file dentro `domain/` o `presentation/`, ti sei sbagliato — quello sta solo in `data/`.

### Stato: Provider

Ogni feature ha un `ProXxx extends ChangeNotifier` che tiene lo stato di presentazione (liste, loading, errori) e chiama gli use case. Niente Riverpod/Bloc.

### Dependency injection: `lib/app.dart`

Non c'è un framework DI: `App.build()` registra tutto a mano con `MultiProvider`, un `Provider`/`ChangeNotifierProvider` per classe, dal datasource fino al `ProXxx`. Per aggiungere una nuova feature, questo è il posto dove va cablata (vedi §7).

---

## 3. Le feature esistenti, una per una

### 3.1 `session/` — chi sei ora (nessun account permanente)

**Entity**: `OnlineSession` (`domain/entities/online_session.dart`) — `sessionId`, `selfiePath`/`selfieBytes`, `gender`, `genderPreference`. Nessun nome, nessuna email.

**Flusso Start** (`UiStartSession` → `ProSession.start(params)`):
1. `StartSessionUseCase` valida che ci sia un selfie non vuoto;
2. chiama `CheckSelfieHasFaceUseCase` (Google ML Kit, **tutto on-device**, nessuna rete) — se non c'è un volto, fallisce;
3. genera `sessionId` con `Uuid().v4()`;
4. `SessionRepositoryImpl.startSession` → `SessionLocalDataSourceImpl` — **una sola variabile in memoria** nel processo dell'app (niente `shared_preferences`, niente disco). Chiudere l'app azzera tutto: è voluto, "usa e getta".

**Start Session non chiama il server.** Il server scopre che esisti solo quando `nearby/` apre la connessione WebSocket (vedi 3.2).

**Flusso End** (`ProSession.end()`, [pro_session.dart:92](lib/features/session/presentation/providers/pro_session.dart#L92)):
1. `StopBeingVisibleUseCase(sessionId)` → `NearbyRepository.stopBeingVisible` → chiude il WebSocket (best-effort: si va avanti anche se la chiusura fallisce). Il server se ne accorge dalla chiusura del socket stesso e rimuove subito la sessione — non serve più un'azione HTTP dedicata;
2. `EndSessionUseCase` → azzera la sessione locale.

`ProSession` accende/spegne anche `WakelockPlus` insieme a Start/End (online lo schermo non va in standby).

### 3.2 `nearby/` — chi c'è vicino (l'unica feature che parla col server vero)

**Entity**: `NearbyPerson` — niente nome, solo `id`, `photoUrl` (il selfie), `distanceMeters`, `meetingChance` (`low`/`medium`/`high`, tre stadi discreti, mai una percentuale).

**Due datasource**:
- `LocationLocalDataSourceImpl` → pacchetto `geolocator`, legge il vero GPS del telefono (permessi, servizio attivo, ecc.) sia una tantum (`getCurrentLocation`) sia in modo continuo (`watchPosition`, vedi sotto).
- `NearbyRemoteDataSourceImpl` → apre e tiene un **WebSocket** (`package:web_socket_channel`) verso il backend vero in `server/`. Base URL da `ApiConfig.wsBaseUrl` (`core/network/api_config.dart`, stesso host di `baseUrl` con schema `ws`/`wss`): `localhost` su web/desktop, `10.0.2.2` sull'emulatore Android, oppure `--dart-define=API_BASE_URL=http://<ip-lan>:8080` per un device fisico.

**Flusso** (`ProNearby._subscribe()`, chiamato una sola volta dal costruttore — niente più timer di polling):

```
WatchNearbyPeopleUseCase.call()  (Stream, non Future)
  ├─ GetCurrentSessionUseCase        (chi sono — locale, se null: "devi essere online")
  ├─ GetCurrentLocationUseCase       (GPS vero — locale, una volta all'apertura)
  ├─ WatchPositionUseCase            (GPS vero, continuo — vedi sotto)
  └─ NearbyRepository.watchNearbyPeople(...)
       └─ NearbyRemoteDataSourceImpl.connect(...)
            └─ apre ws://.../ws?sessionId=...
                 ├─ manda subito {"type":"presence", lat, lng, gender, genderPreference, selfieBase64}
                 └─ resta in ascolto di {"type":"nearby", "people":[...]} spinti dal server
```

Il raggio massimo (100m, `WatchNearbyPeopleUseCase.radiusMeters`) è una costante nello use case, non configurabile dall'esterno; il repository lo riapplica anche lato client come difesa in più, anche se il server ha già filtrato.

**Restare visibili con l'app in background (foreground service, solo Android)**: senza precauzioni Android congela il processo quando l'app va in background — timer che smettono di scattare, socket che restano aperti ma "muti" finché il sistema non li chiude per inattività (dopo di che il server pulisce comunque la sessione con `purgeStale`, ma nel frattempo si sparisce dalla vista degli altri anche stando fisicamente nella zona). `LocationLocalDataSourceImpl.watchPosition()` — chiamato tramite `WatchPositionUseCase` da `WatchNearbyPeopleUseCase` per rimandare la posizione ogni volta che cambia — su Android usa `Geolocator.getPositionStream` con `AndroidSettings(foregroundNotificationConfig: ...)`: questo fa partire un vero **foreground service** nativo (con una notifica persistente, "3mojo è online — Stai comparendo a chi ti è vicino, anche con l'app in background"), che alza la priorità del processo e lo rende molto meno soggetto a essere congelato/ucciso mentre si cambia app. **Non è una garanzia assoluta** (non impedisce la chiusura se l'activity viene proprio distrutta — per quello servirebbe un secondo Flutter engine dedicato, molto più complesso — ma copre il caso comune "ho premuto Home per un attimo"). Sostituisce il vecchio `Timer.periodic` manuale che c'era prima in `WatchNearbyPeopleUseCase` per rimandare la posizione: ora è lo stream del GPS stesso a scandire il ritmo (`intervalDuration: 60s`, `distanceFilter: 0` — stesso intervallo di prima, ma pilotato dal sensore invece che da un timer Dart che si sarebbe congelato per primo).

Richiede quattro permessi in [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml): `FOREGROUND_SERVICE` (Android 9+), `FOREGROUND_SERVICE_LOCATION` (il tipo specifico, obbligatorio da Android 14), `POST_NOTIFICATIONS` (dichiarazione richiesta da Android 13+ perché la notifica sia anche solo *richiedibile*), e `WAKE_LOCK` (obbligatorio perché `ForegroundNotificationConfig.enableWakeLock: true` — **gotcha già capitato**: senza questo permesso `geolocator` non lancia un errore visibile in Dart, ma una `SecurityException` nativa che fa fallire silenziosamente ogni tentativo di `watchPosition()` — la prima posizione (mandata da `getCurrentLocation()` una tantum, prima di aprire lo stream) arriva comunque, ma nessun aggiornamento successivo: la sessione sembra connettersi e poi sparire da sola dopo ~90s, `purgeStale` lato server la pulisce pensandola inattiva).

Su Android 13+ dichiarare `POST_NOTIFICATIONS` nel manifest non basta: va anche **richiesto a runtime**, altrimenti la notifica non compare mai (anche se il servizio in sé parte). `LocationLocalDataSourceImpl.watchPosition()` lo fa con `package:permission_handler` (`Permission.notification.request()`) prima di aprire lo stream — best-effort: se l'utente nega, il tracking va avanti comunque, solo senza notifica visibile.

**Idea per il futuro, non ancora implementata**: dato che il foreground service tiene comunque viva la connessione WebSocket in background, una richiesta d'incontro in arrivo mentre l'app non è in primo piano potrebbe mostrare una notifica locale (`flutter_local_notifications` o simile) — senza bisogno di Firebase/APNs, perché il processo è già vivo e riceve il messaggio sul socket normalmente.

**Auto-riconnessione**: lo stream di `WatchNearbyPeopleUseCase.call()` finisce sempre prima o poi (offline, End premuto, connessione caduta). `ProNearby` lo sa e si riabbona da sola dopo 3s (`_scheduleResubscribe`, chiamato da `onDone` della subscription) — così una volta tornati online, o dopo un blip di rete, la lista riparte senza dover ricreare il provider. **Attenzione se tocchi questo codice**: un `call()` che fallisce subito (es. sessione ancora offline) e poi ritorna, senza questo meccanismo la lista resterebbe morta per sempre dopo il primo fallimento — è già capitato una volta.

**Gotcha da non ripetere**: `WebSocketChannel.connect(uri)` espone un `Future<void> ready` che si completa con errore se la connessione fallisce (host irraggiungibile, timeout). Se nessuno lo legge mai, Flutter lo segnala come "Unhandled Exception" anche se l'errore vero arriva comunque correttamente come evento sullo stream (gestito da `NearbyRepositoryImpl`) — `RealtimeConnection.connect` (vedi sotto) lo marca esplicitamente come "letto" con `unawaited(channel.ready.catchError((_) {}))` proprio per questo.

**Connessione condivisa con `encounters`**: il WebSocket non è più aperto direttamente da `NearbyRemoteDataSourceImpl` — è `RealtimeConnection` ([core/network/realtime_connection.dart](lib/core/network/realtime_connection.dart)) a possedere l'unico canale fisico per sessione, riusato anche da `encounters/` (vedi §3.3). `connect(sessionId)` è idempotente: chi lo chiama per primo apre il socket, gli altri riusano lo stesso; ognuno filtra dallo stream condiviso solo i messaggi del proprio `"type"`. Tenerlo in `core/` invece che dentro `nearby/` evita che `encounters/` debba dipendere da `nearby/` solo per condividere il canale.

Tap su una persona in `CmpNearbyList` → non chiama `nearby/`, chiama `ProEncounters.sendRequest(person.id)` (feature diversa, §3.3).

### 3.3 `encounters/` — richieste d'incontro

**Entity**: `EncounterRequest` con stati `pending`/`accepted`/`declined`/`cancelled`/`ended`. Invariata rispetto a prima — solo `data/` è cambiato, passando da simulazione locale a backend vero.

`EncounterRemoteDataSourceImpl` usa la stessa `RealtimeConnection` condivisa di `nearby/` (nessun secondo socket): `watchRequests(sessionId)` filtra i messaggi `"type":"encounters"` dallo stream condiviso, `sendRequest`/`respondToRequest`/`endMatch` sono fire-and-forget (mandano un messaggio e basta — l'esito arriva col prossimo snapshot pushato dal server, non da un valore di ritorno).

**Regola di business reale — ora applicata dal server, non più dal client**: accettare una richiesta cancella automaticamente tutte le altre pendenti (in entrata e in uscita, **per entrambi** i partecipanti) — `EncounterStore.respondToRequest` ([encounter_store.dart](server/lib/src/encounter_store.dart)) lo fa in un solo posto atomicamente. Prima la regola era divisa tra uno use case client (`RespondToEncounterRequestUseCase` chiamava anche `cancelOtherPendingRequests`) e la simulazione stessa — ora `RespondToEncounterRequestUseCase` è un semplice passacarte, la regola vive per intero lato server (l'unico posto che può davvero saperlo: solo il server conosce le altre richieste pendenti di *entrambe* le parti).

`ProEncounters` non fa più polling ogni 3 secondi: si abbona allo stream di `WatchEncounterRequestsUseCase` esattamente come `ProNearby` fa con `WatchNearbyPeopleUseCase` (stessa auto-riconnessione dopo 3s se lo stream finisce). Espone ancora `activeMatch`: la prima richiesta con stato `accepted` trovata. `_MatchGate` in [app.dart](lib/app.dart#L163) osserva `activeMatch` da qualsiasi punto dell'app e spinge `UiActiveMatch` a schermo intero appena scatta — è così che "un solo incontro alla volta" si ottiene gratis dallo stack di `Navigator`.

Il selfie della controparte (`otherSelfiePath`, in realtà sempre una data URI, mai un vero percorso file — nome storico) non viene mai conservato nella richiesta: il server lo prende fresco da `SessionStore` (`SessionStore.selfieBase64For`) a ogni snapshot, la stessa foto già usata da `nearby/`.

**Gotcha condiviso con `nearby/`**: `Timer`/`Future.delayed` per il resubscribe va tenuto in un campo cancellabile (`Timer? _resubscribeTimer`, cancellato in `dispose()`) — un `Future.delayed` "nudo" senza riferimento non si può fermare, e il widget test lo scopre subito (`A Timer is still pending even after the widget tree was disposed`). Capitato una volta, sistemato in entrambi i provider.

### 3.4 `chat/` — conversazione (locale, nessuna scadenza a tempo)

`ChatLocalDataSourceImpl` salva conversazioni e messaggi come JSON in `shared_preferences` (reale, non finto: il "server farebbe solo da postino", coerente con l'architettura pensata, anche se qui non c'è nessun postino). L'unica parte finta è un autoreply automatico 3s dopo ogni messaggio mandato (`_scheduleFakeReply`), per sentire la chat "viva".

`ProChat` fa polling ogni 2s per vedere l'autoreply senza dover ricaricare manualmente. Nessuna scadenza a tempo: la conversazione dura finché uno dei due non la termina esplicitamente (`EndMatchUseCase`, con conferma in UI).

---

## 4. Il server (`server/`, Dart Frog)

Routing basato su file (convenzione Dart Frog): il path della cartella/file sotto `routes/` diventa l'URL.

```
server/
  routes/
    _middleware.dart      ← CORS, applicato a tutte le route
    ws.dart                → GET /ws?sessionId=...  (upgrade a WebSocket)
    debug/sessions.dart   → GET /debug/sessions   (solo per debug locale)
  lib/src/
    session_store.dart    ← SessionStore: Map<sessionId, Session> in RAM, nessuna persistenza
    encounter_store.dart   ← EncounterStore: Map<requestId, EncounterRequest>, stessa filosofia
    connection_hub.dart    ← ConnectionHub: canali WebSocket connessi, push degli aggiornamenti
    geo.dart               distanza Haversine tra due coordinate
    meeting_chance.dart     soglie di permanenza → low/medium/high
```

**`SessionStore`** è un singleton in RAM (`SessionStore.instance`). Nessun database: riavvii il server e ogni sessione sparisce.

**`GET /ws?sessionId=...`** ([routes/ws.dart](server/routes/ws.dart)) upgrada la richiesta HTTP a WebSocket con `shelf_web_socket` + `fromShelfHandler` (il ponte ufficiale di Dart Frog verso un `shelf.Handler` — necessario perché solo l'oggetto `shelf.Request` sottostante supporta l'hijack richiesto da un upgrade WebSocket). Un solo canale per sessione porta sia presenza/vicinanze sia le richieste d'incontro, distinte da `"type"`:
- `{"type":"presence", "lat":..., "lng":..., "gender":..., "genderPreference":..., "selfieBase64":...}` (alla connessione, e a ogni aggiornamento) → `SessionStore.upsertPosition(...)` seguito da `ConnectionHub.broadcastNearbyUpdates()` — ricalcola e spinge a **ognuno** dei client connessi la propria lista aggiornata;
- `{"type":"sendEncounterRequest","toSessionId":...}`, `{"type":"respondToEncounterRequest","requestId":...,"accepted":...}`, `{"type":"endMatch","requestId":...}` → delegati a `EncounterStore` (vedi sotto), seguiti da `ConnectionHub.pushEncounterSnapshot(...)` per ogni sessione toccata dall'azione (non solo le due dirette: un accept cancella richieste altrui, che vanno notificate anch'esse);
- alla connessione, subito un `ConnectionHub.pushEncounterSnapshot(sessionId)` (stato già esistente, utile dopo una riconnessione — non serve aspettare un cambiamento);
- alla chiusura del socket (`onDone`, pulita o no) → `SessionStore.remove(sessionId)` + `ConnectionHub.unregister(...)` + `broadcastNearbyUpdates()` (chi era connesso a quella persona la vede sparire subito) **e** `EncounterStore.cancelAllPendingFor(sessionId)` + `pushEncounterSnapshot` per ogni controparte toccata — le richieste pendenti di chi sparisce non potrebbero comunque mai ottenere risposta.

**`EncounterStore`** ([encounter_store.dart](server/lib/src/encounter_store.dart)) tiene le richieste d'incontro in RAM, keyed per `requestId`. `respondToRequest(accepted: true)` applica da sola, atomicamente, "un solo incontro alla volta": cancella ogni altra richiesta pendente che coinvolga **l'uno o l'altro** partecipante (non solo le proprie) — prima questa regola era divisa tra client e simulazione, ora vive in un solo posto autoritativo, l'unico che può davvero conoscere le richieste pendenti di entrambe le parti. Il selfie di ognuno non è mai conservato nella richiesta: `ConnectionHub.pushEncounterSnapshot` lo prende fresco da `SessionStore.selfieBase64For(...)` a ogni snapshot.

**Stazionarietà anti-rumore GPS** ([session_store.dart](server/lib/src/session_store.dart)): `Session` tiene due posizioni distinte — `lat`/`lng` (l'ultima nota, usata per le distanze verso gli altri, sempre fresca) e `anchorLat`/`anchorLng` (l'ancora per il calcolo del dwell, più "pigra"). `upsertPosition` sposta l'ancora — e quindi resetta `arrivedAt` — solo dopo **`confirmMovementReadings` (2) letture consecutive** oltre `stationarityRadiusMeters` (**60m**, alzata da 30m) dall'ancora attuale: un singolo balzo GPS isolato che poi torna vicino non conta più come uno spostamento vero. **Perché**: il GPS di uno smartphone normale ha già di suo un errore tipico di 5-20m (anche 30-50m a spot, indoor/urban canyon) — con la soglia più bassa e senza debounce, una singola lettura rumorosa faceva sparire per un altro minuto chi non si era mai davvero mosso (visto ripetutamente in test reali con due telefoni fermi a poche decine di metri).

**`ConnectionHub`** ([connection_hub.dart](server/lib/src/connection_hub.dart)) tiene solo il lato di scrittura (`StreamSink`) di ogni sessione connessa — non lo stream in ingresso, che resta di competenza della route — così è testabile con un semplice `StreamController` senza un vero `WebSocketChannel`. `broadcastNearbyUpdates()` richiama `SessionStore.nearbyPeople(...)` per ognuno (stessi filtri di sempre — genere a senso unico, raggio con Haversine vera in `geo.dart` e **150m** — `ConnectionHub.radiusMeters`, alzato da 100m —, permanenza minima 1 minuto, `meetingChance` da `meeting_chance.dart`) e manda un `{"type":"nearby","people":[...]}` a chi cambia. Il client non riceve **mai** lat/lng grezzi di nessuno, solo distanza + stadio + selfie già pronti. **Attenzione se tocchi il raggio**: è duplicato come costante sia qui (`ConnectionHub.radiusMeters`) sia lato client (`WatchNearbyPeopleUseCase.radiusMeters`, che rifiltra come difesa in più) — vanno tenuti allineati o il più piccolo dei due vince silenziosamente.

**Scadenza automatica delle sessioni** (rete di sicurezza per quando un socket non si chiude in modo pulito — crash, rete che cade): `SessionStore.startAutoPurge(...)` avvia un `Timer.periodic` (ogni 30s di default) che chiama `purgeStale(maxAge)` (90s di default) e rimuove chi non manda un `presence` da troppo tempo; la route `/ws` lo avvia (idempotente) a ogni connessione e collega il callback `onPurged` a `ConnectionHub` per disconnettere/rinotificare gli altri. Questo è **oltre**, non al posto, alla rimozione immediata alla chiusura del socket — la copre nei casi in cui la chiusura non arriva affatto.

- `GET /debug/sessions` → `debugSnapshot()`: bypassa tutti i filtri, elenca sessionId/gender/genderPreference/dwell/lastSeen di tutte le sessioni in memoria, più `distanceMetersToOthers` (distanza calcolata verso ogni altra sessione — derivata, non la posizione grezza) per distinguere al volo "troppo lontani" da "genere/permanenza" quando qualcuno non si vede. Comodo per verificare "chi è arrivato davvero al server" durante i test — non è pensato per restare in un ambiente di produzione reale.

---

## 5. Come si fa girare in locale

```
# Server (dalla cartella server/)
dart pub get
dart pub global activate dart_frog_cli        # una tantum
dart pub global run dart_frog_cli:dart_frog build
dart build/bin/server.dart                     # ascolta su tutte le interfacce, porta 8080 (env PORT)
```

`dart_frog dev` (il comando "ufficiale" con hot reload) **non funziona in un terminale non interattivo** (es. lanciato da script/CI/agenti): prova a leggere da stdin per i tasti di comando e va in crash con `StdinException`. La build di produzione (`dart_frog build` + `dart build/bin/server.dart`) non ha questo problema ed è quella da preferire in quei contesti; in un terminale normale invece `dart_frog dev` va benissimo e dà hot reload.

```
# App (dalla root), device fisico sulla stessa Wi-Fi del PC
flutter run -d <device-id> --dart-define=API_BASE_URL=http://<ip-lan-del-pc>:8080
```

L'IP LAN del PC si trova con `ipconfig` (Windows) cercando `IPv4 Address`. Windows Firewall deve permettere connessioni in entrata sulla porta scelta.

**Se dimentichi `--dart-define=API_BASE_URL=...` su un device fisico**: `ApiConfig.baseUrl` cade sul default per Android (`10.0.2.2`, valido solo per l'emulatore) e la connessione WebSocket va in timeout — si vede in `adb logcat` come `WebSocketChannelException: SocketException: Connection timed out ..., address = 10.0.2.2`. Prima di dare la colpa al codice, controlla sempre questo.

**Gotcha da ambiente Windows incontrati e relative soluzioni**, se ricompaiono:
- `org.gradle.java.home` in `android/gradle.properties` pinnato a un path assoluto — se il repo arriva da un'altra macchina/utente, va ripuntato a un JDK presente su questa macchina (es. quello incluso in Android Studio, `<Android Studio>/jbr`).
- Cache di build Gradle/Kotlin corrotta dopo un'interruzione a metà (`already exists, it cannot be overwritten`, `Storage ... is already registered`) → `flutter clean` + `cd android && ./gradlew --stop` (ferma sia il Gradle Daemon che il Kotlin Compile Daemon rimasti vivi con cache stantie).

---

## 6. Come aggiungere una feature da zero

1. Copia la struttura di `lib/features/nearby/` (l'esempio più completo: datasource remoto+locale, validazione in uno use case, entity+model separati) e rinomina cartelle/file/classi secondo le convenzioni in tabella (§2).
2. Parti dall'**entity** in `domain/entities/`: solo i dati che servono a una regola di business per decidere qualcosa. Un dettaglio tecnico o solo-da-mostrare resta sul **model** (`data/models/`), l'entity non lo vede.
3. Definisci il contratto in `domain/repositories/` (solo `abstract class`), poi lo **use case** in `domain/usecases/` che lo chiama — è lì che vive ogni regola di validazione/business, mai nel provider né nel repository.
4. Implementa `data/datasources/` (`Impl` in file separato dall'interfaccia) e `data/repositories/*_repository_impl.dart`: qui e solo qui si intercettano `Exception` tecniche e si ritorna `Either<Failure, T>`.
5. Presentation: `ProXxx extends ChangeNotifier` che chiama gli use case, poi `UiXxx`/`CmpXxx` che osservano `ProXxx` con `context.watch`/`context.read`.
6. Cablaggio in [lib/app.dart](lib/app.dart): un `Provider`/`ChangeNotifierProvider` per ogni classe nuova, nello stesso ordine di dipendenza (datasource → repository → usecase dentro il provider → ChangeNotifierProvider).
7. Testo utente: mai hardcoded — in `lib/l10n/app_en.arb` (template) e `app_it.arb`, poi `flutter gen-l10n`.
8. Prima di scrivere, ripassa [CHECKLIST.md](CHECKLIST.md): la domanda "cosa sto descrivendo?" toglie quasi tutti i dubbi su dove va un file nuovo.

## 7. Come modificare una feature esistente — esempio pratico

Vuoi aggiungere un nuovo filtro a "Vicinanze" (es. distanza massima configurabile dall'utente invece che fissa a 150m)?

- **Non** toccare `NearbyRemoteDataSourceImpl` per primo: il raggio è già un parametro che passa fino a lì (`radiusMeters`).
- La vera modifica è in `WatchNearbyPeopleUseCase.radiusMeters` (oggi una costante) — diventerebbe un campo passato al `call(...)` dello use case, con eventuale validazione (es. non oltre un massimo ragionevole) proprio lì, non nel provider.
- Se il filtro deve essere "vero" anche lato server (oggi `SessionStore.nearbyPeople`/`ConnectionHub.broadcastNearbyUpdates` usano già `radiusMeters` come parametro/costante), verifica che il valore mandato sul WebSocket sia quello scelto dall'utente e non sempre 150.
- `ProNearby` non cambia: continua ad abbonarsi allo stream di `WatchNearbyPeopleUseCase` — ma non deve mai contenere la logica del filtro.

---

## 8. Test

```
flutter test                 # app: test/widget_test.dart
cd server && dart test       # server: server/test/**
```

I test del server usano `mocktail` per finti `RequestContext`/`Request` di Dart Frog (dove serve — la route `/ws` fa hijack del socket, non testabile con un `RequestContext` finto, quindi non ha un test dedicato: verificata manualmente con un client WebSocket vero, vedi i commit che hanno introdotto `/ws` per lo script di prova usato), un `SessionStore.withClock(...)` con orologio controllabile (invece del singleton con `DateTime.now()` reale) per testare deterministicamente le soglie di permanenza, e analoghi `ConnectionHub.withStore(...)`/`EncounterStore.empty()` per testare broadcast ed esclusività con istanze indipendenti dai singleton condivisi (altrimenti i test si "sporcherebbero" a vicenda, dato che non c'è modo di resettare un singleton tra un test e l'altro).
