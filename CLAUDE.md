# 3mojo_app

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
| data/datasources | `*_data_source.dart` (+ `_impl.dart`) | `XxxDataSource` (+`Impl`) |
| domain/usecases | `*_usecase.dart` | `XxxUseCase` |

Interfaccia e implementazione **sempre in due file separati**, mai nello stesso file — anche quando stanno nello stesso layer (es. i data source).

## Le tre domande da farsi scrivendo codice

**1. Questa interfaccia va in `domain/` o resta in `data/`?**
→ *C'è una classe dentro `domain/` che deve importarla e chiamarla direttamente?*
Sì (es. `TodoRepository`, chiamata dagli use case) → `domain/repositories/`.
No (es. `TodoLocalDataSource`, chiamata solo da `XxxRepositoryImpl`) → resta in `data/`, anche se ha un'interfaccia e un'implementazione separate.

**2. Questo nuovo campo/proprietà va sull'entity (`domain/entities`) o solo sul model (`data/models`)?**
→ *Uno use case o una regola di business deve leggere questo valore per decidere qualcosa?*
Sì → va sull'entity (e sul model, per portarlo dal JSON).
No, serve solo a essere mostrato o è un dettaglio tecnico del server (es. un `_etag` di sincronizzazione) → resta solo sul model, l'entity non lo vede mai.
Attenzione: "si vede in UI" non è il test giusto — un dato già presente sull'entity può essere solo *riformattato* nel widget senza toccare domain/data (es. "creato 2 minuti fa" da un `createdAt` che esiste già).

**3. Dove metto una regola di business (validazioni, vincoli)?**
→ Nello **use case** corrispondente, mai nel provider (gestisce solo stato UI) né nel repository (gestisce solo accesso ai dati). Esempio: `AddTodoUseCase` valida il titolo prima di chiamare il repository.

## Regola d'oro sulle dipendenze

Ogni freccia di chiamata scende: `presentation → domain → data`.
Ogni freccia `implements`/`extends` punta all'indietro, verso `domain/`, **mai in uscita**: `XxxRepositoryImpl implements XxxRepository`, `XxxDataSourceImpl implements XxxDataSource`, `XxxModel extends Xxx`.
Se ti accorgi di dover importare qualcosa da `data/` dentro `domain/`, hai sbagliato direzione — fermati.

## Error handling

- `data/`: lancia `Exception` proprie (`core/errors/exceptions.dart` — `ServerException`, `CacheException`), mai `Failure`.
- Il repository (in `data/`) intercetta le `Exception` e le traduce in `Failure` (`core/errors/failures.dart`), ritornando `Either<Failure, T>` (fpdart).
- Da `domain/` in su, si parla solo `Either<Failure, T>` — mai try/catch su eccezioni tecniche nel provider o nella UI.

## Stato e altro

- State management: **Provider** (`ChangeNotifier`), niente Riverpod/Bloc.
- i18n: `flutter gen-l10n` — stringhe utente in `lib/l10n/app_en.arb` (template) e `app_it.arb`, mai testo hardcoded nei widget. Rigenerare con `flutter gen-l10n` dopo ogni modifica agli ARB.
- JDK per build Android: pinnato in `android/gradle.properties` (`org.gradle.java.home`) — non cambiare senza motivo.

## Esempi di riferimento nel codice

- `lib/features/session/` — **niente account permanente**: "chi sei" è solo `OnlineSession` (selfie + genere + preferenza), fatto e disfatto a ogni Start/End, tenuto **solo in memoria** (`SessionLocalDataSourceImpl` non usa `shared_preferences`/disco: chiudere del tutto l'app e riaprirla riparte sempre da zero, mai un `deviceId` fisso — non serve, i finti datasource non lo usano). Nessun `Model`/JSON (come `counter` a suo tempo): il datasource legge/scrive l'entity direttamente. Validazione reale in `StartSessionUseCase` (serve un selfie). `UiHome` è un'unica pagina che cambia aspetto in base a `ProSession.isOnline` — non due pagine separate. Da online, è anche l'unica pagina per vedere le persone vicine: niente pagina separata col proprio selfie centrato, il body mostra direttamente `CmpNearbyList` (feature `nearby`), l'AppBar ha il bottone End (rosso), e la bottom app bar mostra solo il proprio selfie in piccolo più l'icona "Richieste". `ProSession` accende/spegne anche il wakelock (`WakelockPlus`, pacchetto `wakelock_plus`) insieme a Start/End: online lo schermo non va in standby, offline torna al comportamento normale. Il selfie viene anche corretto (ribaltato una volta, `package:image`) perché molte fotocamere frontali Android lo salvano speculare, e validato con `CheckSelfieHasFaceUseCase` (Google ML Kit, tutto sul dispositivo — nessun dato biometrico salvato/inviato, solo "c'è un volto sì/no") per impedire di usare un'immagine a caso: la regola vera vive nello use case (composto anche da `StartSessionUseCase`, come sotto-passo), la UI lo richiama subito dopo lo scatto solo per un feedback immediato.
- `lib/features/nearby/` — due data source, uno **reale** (`LocationLocalDataSourceImpl`, pacchetto `geolocator`, per la posizione del proprio telefono) e uno **finto** (`NearbyRemoteDataSourceImpl`, simula un backend non ancora esistente, con fallimenti casuali e uno stato di presenza per persona che cambia a ogni fetch — non è una lista statica). Uno use case (`GetNearbyPeopleUseCase`) compone un altro use case (`GetCurrentLocationUseCase`) invece di dipendere direttamente dal suo repository — pattern accettabile quando un'azione è un sotto-passo genuino di un'altra. La regola di business "raggio massimo 100 metri" è una costante nello use case, non un parametro configurabile dall'esterno. `NearbyPerson` non ha un nome (l'app non lo chiede mai): solo foto, distanza, e stadio di probabilità d'incontro.
- Regola di business su `NearbyPerson.meetingChance`: **tre soli stadi discreti** (`low`/`medium`/`high`, niente percentuale continua né barra di progresso in UI) in base a quanto la persona è rimasta ferma nello stesso posto — bassa da 1 minuto, media da 3, alta da 5 — e la persona resta invisibile in lista finché non ha almeno 1 minuto di presenza. È calcolato **lato server** (richiede la storia di posizione di un'altra persona, che il client non può conoscere) — il client riceve solo lo stadio già pronto. Nel finto datasource il tempo di permanenza si calcola da un vero `arrivedAt` (`DateTime.now().difference(...)`), non da quante volte è stato chiamato `fetchNearbyPeople()`: se una persona finta è "arrivata" prima che tu iniziassi a guardare, la vedi già ad alta probabilità al primo caricamento, non solo dopo N tuoi refresh — coerente con un vero server che tiene il proprio orologio indipendentemente da chi lo interroga.
- `lib/features/encounters/` — richiesta d'interesse tra due persone (tap sulla foto in `nearby` → richiesta in uscita; l'altro la vede in entrata e risponde sì/no). Regola di business reale in `RespondToEncounterRequestUseCase`: accettarne una **cancella automaticamente tutte le altre** (in entrata e in uscita) — un solo incontro attivo alla volta. Il rifiuto è visibile a chi ha chiesto (scelta deliberata, diversa dalla convenzione delle app di dating classiche — qui ha senso perché ci si potrebbe incontrare fisicamente). Data source finto e **stateful** (simula sia risposte in arrivo alle tue richieste sia richieste finte che ricevi tu, e applica da solo la stessa regola di esclusività quando è "il finto altro" ad accettare — coerente con come si comporterebbe un vero backend), con polling periodico nel provider (`Timer.periodic`).
- `lib/features/chat/` — niente scadenza a tempo: la conversazione dura finché nessuno dei due la termina esplicitamente (`EndMatchUseCase`, con conferma obbligatoria in UI — "perderai il contatto"). Storage **locale** (`shared_preferences`, JSON codificato) — coerente con "il server fa solo da postino, non conserva nulla".
- Flusso app (`app.dart`): **niente `_AppRoot` con gate sequenziali** — `UiHome` decide da sola cosa mostrare in base a `ProSession.isOnline`. Sopra tutto, `_MatchGate` osserva `ProEncounters.activeMatch`: appena un match scatta (da qualsiasi punto dell'app), spinge `UiActiveMatch` a schermo intero sopra qualunque pagina — è così che "un solo incontro alla volta" si ottiene gratis dallo stack di `Navigator`, senza dover disabilitare manualmente le altre pagine.
