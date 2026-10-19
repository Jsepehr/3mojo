# 3mojo_app

Per l'utente l'app si chiama **Raen** (nome mostrato su Android/iOS, testi ARB, canale nativo `raen/face_detection`); il progetto e i pacchetti Dart si chiamano `threemojo_app` (questa app, `lib/`) e `threemojo_server` (backend Dart Frog, `server/`).

App Flutter organizzata per **feature, in clean architecture** (`presentation` → `domain` ← `data`). Prima di scrivere codice in una feature esistente o crearne una nuova, segui le regole sotto — non sono stile, sono la ragione per cui l'app rimane facile da cambiare.

Prima di creare un nuovo file, consulta anche [CHECKLIST.md](CHECKLIST.md): stessa logica, ma come lista di domande passo per passo.

## Struttura di una feature

```
lib/features/<nome>/
  data/
    datasources/   <nome>_remote_data_source.dart (+_impl)   ← se serve una fonte remota
                   <nome>_local_data_source.dart (+_impl)    ← se serve una cache/DB
    models/        <nome>_model.dart        (estende l'entity, aggiunge fromJson/toJson)
    repositories/  <nome>_repository_impl.dart
  domain/
    entities/      <nome>.dart               (classe pura, Equatable, niente JSON)
    repositories/   <nome>_repository.dart    (solo abstract class — il contratto)
    usecases/      <azione>_usecase.dart      (una classe = un'azione)
  presentation/
    pages/         ui_<nome>.dart             (classe UiXxx)
    providers/     pro_<nome>.dart            (classe ProXxx, ChangeNotifier)
    widgets/       cmp_<nome>.dart            (classe CmpXxx)
```

Per una feature nuova: copia la struttura di `lib/features/nearby/` o `lib/features/encounters/` (vedi sotto) e rinomina.

## Convenzioni di naming

| Layer | File | Classe |
|---|---|---|
| presentation/pages | `ui_*.dart` | `UiXxx` |
| presentation/widgets | `cmp_*.dart` | `CmpXxx` |
| presentation/providers | `pro_*.dart` | `ProXxx` |
| domain/repositories | `*_repository.dart` | `XxxRepository` (abstract) |
| data/repositories | `*_repository_impl.dart` | `XxxRepositoryImpl` |
| data/datasources | `*_data_source.dart` (+ `_impl.dart`, `_fake_impl.dart`) | `XxxDataSource` (+`Impl`, `FakeImpl`) |
| domain/usecases | `*_usecase.dart` | `XxxUseCase` |

Interfaccia e implementazione **sempre in due file separati**, mai nello stesso file — anche quando stanno nello stesso layer (es. i data source). I `*_fake_impl.dart` simulano il backend senza rete (modalità finta, solo nei build di debug). Un traduttore da valori/`Failure` a testo che non è un widget sta direttamente in `presentation/` (es. `session_failure_texts.dart`, `profile_labels.dart`).

## Le tre domande da farsi scrivendo codice

**1. Questa interfaccia va in `domain/` o resta in `data/`?**
→ *C'è una classe dentro `domain/` che deve importarla e chiamarla direttamente?*
Sì (es. `NearbyRepository`, chiamata dagli use case) → `domain/repositories/`.
No (es. `LocationLocalDataSource`, chiamata solo da `LocationRepositoryImpl`) → resta in `data/`, anche se ha un'interfaccia e un'implementazione separate.

**2. Questo nuovo campo/proprietà va sull'entity (`domain/entities`) o solo sul model (`data/models`)?**
→ *Uno use case o una regola di business deve leggere questo valore per decidere qualcosa?*
Sì → va sull'entity (e sul model, per portarlo dal JSON).
No, serve solo a essere mostrato o è un dettaglio tecnico del server (es. un `_etag` di sincronizzazione) → resta solo sul model, l'entity non lo vede mai.
Attenzione: "si vede in UI" non è il test giusto — un dato già presente sull'entity può essere solo *riformattato* nel widget senza toccare domain/data (es. "creato 2 minuti fa" da un `createdAt` che esiste già).

**3. Dove metto una regola di business (validazioni, vincoli)?**
→ Nello **use case** corrispondente, mai nel provider (gestisce solo stato UI) né nel repository (gestisce solo accesso ai dati). Esempio: `SaveProfileUseCase` valida età, lingue e consenso prima di chiamare il repository.

## Regola d'oro sulle dipendenze

Ogni freccia di chiamata scende: `presentation → domain → data`.
Ogni freccia `implements`/`extends` punta all'indietro, verso `domain/`, **mai in uscita**: `XxxRepositoryImpl implements XxxRepository`, `XxxDataSourceImpl implements XxxDataSource`, `XxxModel extends Xxx`.
Se ti accorgi di dover importare qualcosa da `data/` dentro `domain/`, hai sbagliato direzione — fermati.

## Error handling

- `data/`: lancia `Exception` proprie (`core/errors/exceptions.dart` — `ServerException`, `CacheException`), mai `Failure`.
- Il repository (in `data/`) intercetta le `Exception` e le traduce in `Failure` (`core/errors/failures.dart`), ritornando `Either<Failure, T>` (fpdart).
- Da `domain/` in su, si parla solo `Either<Failure, T>` — mai try/catch su eccezioni tecniche nel provider o nella UI.
- Ogni errore da mostrare ha un `Failure` **tipizzato** (es. `NoFaceInSelfieFailure`, `ConnectionFailure`): la UI sceglie il testo tradotto dal tipo (`SessionFailureTexts`, `ProfileLabels`, `CmpNearbyErrorState`…), **mai** da `failure.message`, che è solo un dettaglio tecnico.

## Stato e altro

- State management: **Provider** (`ChangeNotifier`), niente Riverpod/Bloc.
- i18n: `flutter gen-l10n` — stringhe utente in `lib/l10n/app_en.arb` (template) e nelle altre lingue (`app_it`, `app_de`, `app_es`, `app_fr`, `app_ar`), mai testo hardcoded nei widget. Rigenerare con `flutter gen-l10n` dopo ogni modifica agli ARB.
- JDK per build Android: `android/gradle.properties` fissa `org.gradle.java.home` a un percorso assoluto di una macchina Windows (`C:\Users\sepehrbaradaran\.jdks\azul-17.0.16`), valido solo lì: su un'altra macchina la build fallisce finché non lo si adatta (percorsi noti in [macchine_sviluppo.md](macchine_sviluppo.md)). Non cambiarlo nel repository senza motivo.

## Esempi di riferimento nel codice

- `lib/features/session/` — **niente account permanente**: "chi sei" è solo `OnlineSession` (`selfieBytes` + copia del profilo + intento), fatta e disfatta a ogni Start/End e tenuta **solo in memoria** (`SessionLocalDataSourceImpl`: niente disco, niente `deviceId`, nessun Model/JSON). `StartSessionUseCase` valida selfie, profilo (compone `GetProfileUseCase`) e volto (compone `CheckSelfieHasFaceUseCase`: tutto sul dispositivo, canale nativo `raen/face_detection` — ML Kit in `FaceDetectionChannel.kt`, Apple Vision in `AppDelegate.swift`, **non** il plugin `google_mlkit_face_detection`, che impediva di avviare l'app sul simulatore iOS di un Mac Apple Silicon; la UI lo richiama dopo lo scatto solo per un feedback immediato). Selfie: `TakeSelfieUseCase` (il file della fotocamera è cancellato appena letto), `FlipSelfieUseCase` (lo decide l'utente col bottone; metadati tolti), `DiscardSelfieFilesUseCase` a End. `EndSessionUseCase` chiude prima la sessione locale, poi i passi delle altre feature iniettati come `SessionTeardownUseCase` (in parallelo, max 3 s ciascuno): `session/` non importa nessuna di loro. `WatchSessionUseCase` è lo stream Start/End su cui `ProNearby`/`ProEncounters`/`ProChat`/`ProPaywall` partono e si fermano. `ProSession` accende/spegne il wakelock (`wakelock_plus`); `ProConnection` + `CmpConnectionBanner` mostrano la riconnessione. `UiHome` è un'unica pagina che cambia con `ProSession.isOnline`: online ha End (rosso) nell'AppBar, `CmpPaywalledNearbyList` nel body, il proprio selfie e "Richieste" in basso.
- `lib/features/nearby/` — `LocationLocalDataSourceImpl` (`geolocator`; su Android foreground service per restare visibili in background) e `NearbyRemoteDataSourceImpl` (stream **push** sul WebSocket condiviso) o, in modalità finta, `NearbyRemoteDataSourceFakeImpl`. `WatchNearbyPeopleUseCase` compone `GetCurrentSessionUseCase`, `GetCurrentLocationUseCase` e `WatchPositionUseCase` (sotto-passi genuini). Chi è visibile lo decide **solo il server**: raggio `ConnectionHub.radiusMeters` (100 m, 200 m dentro uno stesso hotspot di `HotspotStore`), matching reciproco, almeno 1 minuto fermi; il client non rifiltra. `NearbyPerson` non ha nome né distanza (il server non la manda: servirebbe a trilaterare): id = **pseudonimo per osservatore**, foto, `isLocked` (paywall, deciso dal server), ciò che la persona mostra del profilo e `meetingChance` — **tre stadi discreti** (`low`/`medium`/`high` da 1/3/5 minuti fermi, mai percentuali), calcolati lato server; il finto li calcola da un vero `arrivedAt`.
- `lib/features/encounters/` — tap su una foto → richiesta; l'altro risponde sì/no; il rifiuto è visibile a chi ha chiesto (scelta deliberata: ci si può incontrare di persona). Regole **sul server** (`EncounterStore`, `RealtimeMessageHandler`): un sì cancella tutte le altre pendenti di entrambi (un incontro alla volta); una sola richiesta per coppia per tutta la sessione, anche se rifiutata (`alreadyRequested`, replicata nel client da `HasRequestedPersonUseCase` per use case e UI); solo verso chi è in "Vicinanze" e non bloccato. I rifiuti tornano come `rejected` (`WatchEncounterRejectionsUseCase` → `CmpEncounterNoticeListener`); una richiesta mai confermata entro 10 s è persa (`FindLostEncounterRequestsUseCase`). "Il match è finito dall'altra parte" e la cancellazione della sua chat stanno in `DetectEndedMatchUseCase`, non nel provider. Snapshot spinti dal server, niente polling; il finto è stateful e applica le stesse regole.
- `lib/features/chat/` — nessuna scadenza: dura finché non si chiude il match (`EndMatchUseCase`, con conferma) o la sessione. Cronologia **solo in memoria** (`ChatRemoteDataSourceImpl`; il server fa solo da postino, e solo con un match attivo); `purgeLegacyChatStorage` cancella le chat salvate in `shared_preferences` dalle versioni vecchie. La ricezione parte all'inizio della sessione (`StartReceivingChatMessagesUseCase`), così i messaggi arrivati prima che la pagina del match si apra non si perdono. Testo al massimo 1000 unità UTF-16 (`SendMessageUseCase`, allineato al server). Un messaggio non partito o non consegnato resta "non inviato" e si può rimandare; `ProChat.close` svuota la chat quando la pagina del match si chiude.
- `lib/features/profile/` — compilato **una volta** (`UiHome` mostra `UiProfile` finché manca) e modificabile dal menu: genere, chi vuoi incontrare, 18+, intento predefinito, max 2 lingue, "mostra il mio genere". **Cifrato sul telefono** (`flutter_secure_storage`, `allowBackup="false"`), mai sul server se non in RAM durante la sessione. Genere + chi cerchi = dato sensibile: `SaveProfileUseCase` esige il consenso, tranne con "preferisco non dirlo" + "tutti". Agli altri mai chi cerchi. Cancellarlo da online chiude prima la sessione (`WithdrawProfileUseCase`, in `session/`); `WipeDataFromPreviousInstallUseCase` (in `main.dart`) cancella ciò che il Keychain iOS conserva dopo una reinstallazione. Sul server: `PresenceProfile` (liste chiuse, profilo fissato alla nascita della sessione) e `NewSessionRateLimiter`.
- `lib/features/paywall/` — sblocco di 2 ore, regola e orologio **lato server** (`PaywallStore`): un terzo dei più lontani gratis (min 2), gli altri arrivano `locked` senza foto; `GetLockedNearbyPeopleUseCase` riordina e basta. Token casuale per acquisto in `UnlockTokenStore` (`core/unlock/`, `flutter_secure_storage`, solo finché vale) — **mai un id del dispositivo**. Pagamento ancora finto (`PurchaseUnlockUseCase`).
- `lib/core/` — `RealtimeConnection`: un solo WebSocket per sessione, condiviso da nearby/encounters/chat; segreto nel primo messaggio (`hello`), ping ogni 20 s, riconnessione con backoff (`ReconnectBackoff`); una caduta non chiude lo stream (errore → `ConnectionFailure`) e il server tiene la sessione 45 s. Al ritorno in primo piano `ProConnection` → `CheckConnectionUseCase` → `checkAlive` (ping/pong, riconnessione se muto); un End durante la riconnessione manda comunque `end` su un socket d'addio. Protocollo: `server/routes/ws.dart`. Widget condivisi in `core/widgets/` (`CmpPhoto`, `CmpLoadingIndicator`, `CmpRadarBackground`…). Datasource `*FakeImpl` solo nei build di debug (`App.fakeModeAvailable`).
- Flusso app (`app.dart`): nessun gate sequenziale, `UiHome` decide da sola. Sopra tutto `CmpMatchGate` (`encounters/presentation/widgets/`) segue `ProEncounters.activeMatch`: apre `UiActiveMatch` a schermo intero e la chiude quando il match finisce — "un incontro alla volta" viene gratis dallo stack di `Navigator`. Privacy di piattaforma: `FLAG_SECURE` (`MainActivity.kt`), copertura nel multitasking iOS (`PrivacyCover`, solo quando l'app va in background, non dietro ai dialoghi di permesso).
