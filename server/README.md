# threemojo_server

[![style: dart frog lint][dart_frog_lint_badge]][dart_frog_lint_link]
[![License: MIT][license_badge]][license_link]
[![Powered by Dart Frog](https://img.shields.io/endpoint?url=https://tinyurl.com/dartfrog-badge)](https://dart-frog.dev)

Backend [Dart Frog](https://dart-frog.dev) dell'app **Raen** (`threemojo_app`,
nella cartella superiore). Tiene tutto **solo in RAM** (sessioni, richieste
d'incontro, sblocchi, hotspot): riavviarlo cancella tutto. Architettura e
regole sono spiegate in [../guida_per_sviluppatori.md](../guida_per_sviluppatori.md) (§4).

[dart_frog_lint_badge]: https://img.shields.io/badge/style-dart_frog_lint-1DF9D2.svg
[dart_frog_lint_link]: https://pub.dev/packages/dart_frog_lint
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT

## Avvio

```
dart pub get
dart pub global run dart_frog_cli:dart_frog build
dart build/bin/server.dart        # porta 8080 (env PORT)
```

In un terminale interattivo va bene anche `dart_frog dev` (hot reload); da
script/CI/agenti no: legge da stdin e va in crash con `StdinException`.

Route: `GET /` (controllo di salute), `GET /ws` (WebSocket), `POST
/paywall/purchase`, `POST /paywall/status`, `GET /debug/sessions` (spento di
default).

## Variabili d'ambiente

| Variabile | Effetto |
|---|---|
| `TLS_CERT_PATH` + `TLS_KEY_PATH` | Percorsi di catena di certificati e chiave privata (PEM). Se presenti entrambe il server parla **solo** `https://`/`wss://` (vedi `main.dart`). Con una sola delle due si rifiuta di partire. |
| `DEBUG_ENDPOINTS_TOKEN` | Accende `GET /debug/sessions`, che risponde solo con l'header `X-Debug-Token` uguale a questo valore. Senza, l'endpoint risponde 404. Da non impostare in produzione. Non espone posizioni né distanze tra persone. |
| `MAX_NEW_SESSIONS_PER_IP` | Quanti nuovi Start (hello con un segreto nuovo) ammette lo stesso IP ogni 10 minuti (`NewSessionRateLimiter`). Default 20; un valore non intero o ≤ 0 è ignorato. Da alzare solo per le prove in locale (es. `200` col simulatore, che da solo apre 20 sessioni). |
| `TRUSTED_PROXY` | IP dei reverse proxy fidati, separati da virgola (es. `127.0.0.1,10.0.0.5`). Solo per le connessioni che arrivano da uno di questi si legge `X-Forwarded-For` per i limiti per IP (nuovi Start su `/ws`, `POST /paywall/purchase`). Vuoto = l'header è ignorato (chiunque potrebbe falsificarlo). Dietro un proxy **va impostato**, altrimenti tutti i client sembrano lo stesso IP. |

Senza `TLS_*` il server resta in chiaro: va bene in sviluppo locale, in
produzione **solo** dietro un reverse proxy che termina TLS. L'app in release
accetta comunque solo `API_BASE_URL=https://…`.

## WebSocket `/ws`

Il protocollo completo (messaggi e campi) è documentato in testa a
`routes/ws.dart`: quella è la fonte di verità.

**Autenticazione**: il segreto di sessione arriva col **primo messaggio**
(`{"type":"hello","secret":...}`, entro 10 s), mai nell'URL. Il server lo
traduce in un id interno casuale (`SessionCredentials`) che non esce mai dal
server, e risponde `welcome` oppure `error` (`invalidSecret`/`rateLimited`)
chiudendo il socket. Agli altri utenti arrivano solo **pseudonimi per
osservatore** (`Pseudonyms`): la stessa persona ha un id diverso per ognuno
che la vede. Nessuna distanza viene mai mandata ai client.

**Grazia**: una caduta della connessione non chiude subito la sessione: per
45 s (`SessionLifecycle`) la sessione è nascosta ma intatta, e riconnettersi
con lo stesso segreto la riprende (stesso id, permanenza, richieste e match;
`welcome` con `resumed: true`). Solo `{"type":"end"}`, la scadenza della
grazia o 90 s senza messaggi (il client manda un `ping` ogni 20 s) la
chiudono. A ogni `ping` il server risponde `{"type":"pong"}`: l'app lo usa
per accorgersi di un socket morto quando torna in primo piano.

**Vicinanze**: raggio 100 m (200 m dentro uno stesso hotspot), matching
reciproco, ed entrambi fermi da almeno un minuto — **anche chi guarda**: la
sua lista è vuota per il primo minuto e dopo ogni spostamento confermato. Le
distanze vanno da **ancora ad ancora** (il punto in cui ognuno è fermo,
congelato dopo il primo minuto), mai dall'ultima lettura grezza: chi
falsifica il GPS non può più sondare la posizione altrui a piccoli passi. La
lista è ordinata per fasce di 25 m, senza distanze (vedi `SessionStore`).

**Selfie nelle richieste**: lo snapshot `encounters` porta il selfie della
controparte solo la prima volta per ogni richiesta su ogni socket; gli
snapshot successivi lo omettono e il client riusa quello già ricevuto.

## Limiti

| Cosa | Limite | Dove |
|---|---|---|
| Nuovi Start (hello con un segreto nuovo) | 20 per IP ogni 10 minuti (configurabile, `MAX_NEW_SESSIONS_PER_IP`); le riconnessioni non contano | `NewSessionRateLimiter` |
| `POST /paywall/purchase` | 10 per IP ogni 10 minuti | `purchaseRateLimiter` in `rate_limiters.dart` |
| Messaggi per connessione | 20 di fila, poi 5 al secondo; oltre si scartano, dopo 50 scarti di fila il socket si chiude (4029) | `ConnectionRateLimiter` |
| Dimensione di un messaggio | 320 KB `presence`, 16 KB `chatMessage`, 1 KB il resto (oltre, il socket si chiude con 4009) | `RealtimeMessageHandler.maxCharsFor` |
| Selfie | solo JPEG, ≤ ~230 KB, metadati tolti | `SelfieValidator` |
| Testo di chat | 1000 unità UTF-16 (come `SendMessageUseCase` nell'app); oltre → `rejected` `invalidText`, il socket resta aperto. Inoltrato solo con un match attivo | `RealtimeMessageHandler` |
| Richieste d'incontro pendenti | 5 in uscita, 20 in entrata per sessione | `EncounterStore` |
| Spostamenti | oltre 50 m/s (+250 m di tolleranza GPS) la presenza è scartata | `SessionStore.upsertPosition` |
| Posizioni | al più una utile ogni 10 s per sessione; quelle in più sono ignorate in silenzio (`tooSoon`, nessun rifiuto, socket aperto) | `SessionStore.minPositionInterval` |
| Liste `nearby` | al più una diversa ogni 5 s per osservatore (le modifiche nel frattempo partono alla fine della finestra), oltre al throttle globale di 500 ms | `ConnectionHub.nearbyPushMinInterval` |

## Simulatore di dispositivi

```
dart run tool/simulate_fake_devices.dart [wsBaseUrl]   # default ws://localhost:8080
```

Col server già acceso, apre 20 connessioni WebSocket vere (stesso protocollo
dell'app: `hello`, `presence` ogni 20 s, `end` alla chiusura) disposte per far
vedere visibilità normale e hotspot (che si formano dopo 15 minuti). Dettagli
nel commento del file. Venti Start dallo stesso IP sono esattamente il tetto
di `NewSessionRateLimiter`: rilanciarlo entro 10 minuti può essere rifiutato
(`rateLimited`), e il simulatore lo ricorda all'avvio. Per le prove avvia il
server con `MAX_NEW_SESSIONS_PER_IP=200`.

## Test

```
dart test
```
