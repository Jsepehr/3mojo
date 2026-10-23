# threemojo_server

[![style: dart frog lint][dart_frog_lint_badge]][dart_frog_lint_link]
[![License: MIT][license_badge]][license_link]
[![Powered by Dart Frog](https://img.shields.io/endpoint?url=https://tinyurl.com/dartfrog-badge)](https://dart-frog.dev)

Backend [Dart Frog](https://dart-frog.dev) dell'app **Raen** (`threemojo_app`,
nella cartella superiore). Tiene **solo in RAM** tutto lo stato di sessione
(sessioni, richieste d'incontro, chat inoltrate, blocchi, segnalazioni,
sblocchi, transazioni riscattate, hotspot): riavviarlo lo cancella. **Unica eccezione**: i record di
moderazione (vedi [Segnalazioni e moderazione](#segnalazioni-e-moderazione)),
cifrati su disco e cancellati dopo 30 giorni. Architettura e regole sono
spiegate in [../guida_per_sviluppatori.md](../guida_per_sviluppatori.md) (§4).

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
/paywall/purchase`, `POST /paywall/status`, `POST
/paywall/notifications/apple` e `/google` (spente di default, vedi
[Pagamenti](#pagamenti-in-app)), `GET /debug/sessions` (spento di
default), `GET /admin/reports`, `GET /admin/reports/<id>/selfie`, `DELETE
/admin/reports/<id>` (spenti di default, vedi sotto).

`POST /paywall/purchase` riceve un acquisto in-app `{"platform":
"ios"|"android"|"fake", "productId", "receipt", "transactionId"}`, lo
**verifica col negozio** e solo allora risponde `{"unlockToken",
"expiresInSeconds", "remainingSeconds", "alreadyRedeemed"}` (codici di errore
in testa a `routes/paywall/purchase.dart`). `POST /paywall/status`
(`{"unlockToken"}` nel corpo) risponde `{"isUnlocked", "remainingSeconds"}`.
`remainingSeconds` è il tempo **residuo** dello sblocco sull'orologio del
server (`PaywallStore.remainingFor`, per difetto, `0` se non vale): il client
ne ricava la scadenza come "sua ora alla risposta + residuo" e la riallinea a
ogni status, così l'orologio del telefono non conta. `expiresInSeconds` resta
per i client già usciti.

## Variabili d'ambiente

| Variabile | Effetto |
|---|---|
| `TLS_CERT_PATH` + `TLS_KEY_PATH` | Percorsi di catena di certificati e chiave privata (PEM). Se presenti entrambe il server parla **solo** `https://`/`wss://` (vedi `main.dart`). Con una sola delle due si rifiuta di partire. |
| `DEBUG_ENDPOINTS_TOKEN` | Accende `GET /debug/sessions`, che risponde solo con l'header `X-Debug-Token` uguale a questo valore. Senza, l'endpoint risponde 404. Da non impostare in produzione. Non espone posizioni né distanze tra persone. |
| `MAX_NEW_SESSIONS_PER_IP` | Quanti nuovi Start (hello con un segreto nuovo) ammette lo stesso IP ogni 10 minuti (`NewSessionRateLimiter`). Default 20; un valore non intero o ≤ 0 è ignorato. Da alzare solo per le prove in locale (es. `200` col simulatore, che da solo apre 20 sessioni). |
| `TRUSTED_PROXY` | IP dei reverse proxy fidati, separati da virgola (es. `127.0.0.1,10.0.0.5`). Solo per le connessioni che arrivano da uno di questi si legge `X-Forwarded-For` per i limiti per IP (nuovi Start su `/ws`, `POST /paywall/purchase`). Vuoto = l'header è ignorato (chiunque potrebbe falsificarlo). Dietro un proxy **va impostato**, altrimenti tutti i client sembrano lo stesso IP. |
| `MODERATION_KEY` | Chiave AES-256-GCM dei record di moderazione: 32 byte in base64, es. `openssl rand -base64 32`. **Senza (o non valida) i record non vengono salvati** e il server lo scrive nel log all'avvio; blocchi, soglie e chiusura automatica funzionano lo stesso. Tenerla fuori dal repository e dai backup dei record: chi ha i file senza la chiave non legge nulla. Cambiarla rende illeggibili i record vecchi (spariscono comunque entro 30 giorni dalla data del file). |
| `MODERATION_DIR` | Cartella dei record (un file `<id>.rec` per record). Default `moderation_records` nella cartella di lavoro. Creata con permessi `700` dove possibile; va su un disco non condiviso. |
| `ADMIN_TOKEN` | Accende gli endpoint `/admin/reports` (header `Authorization: Bearer <token>`, confronto a tempo costante). Almeno 32 caratteri (es. `openssl rand -hex 32`), altrimenti restano spenti (404) e il server lo scrive nel log. |
| `ADMIN_ALLOW_INSECURE_HTTP` | `true` = gli endpoint admin rispondono anche in chiaro, **solo** a connessioni da loopback (sviluppo locale). In ogni altro caso servono TLS diretto (`TLS_*`) o un proxy fidato (`TRUSTED_PROXY`) che mandi `X-Forwarded-Proto: https`, altrimenti 403. |
| `MODERATION_AUTO_CLOSE_REPORTS` | Da quante sessioni diverse deve essere segnalata una sessione per essere chiusa da sola. Default 3. |
| `MODERATION_AUTO_CLOSE_MIN_IPS` | Da quanti IP diversi devono arrivare quelle segnalazioni. Default 2 (se nessun segnalatore ha un IP noto, la condizione è ignorata). |
| `PAYMENTS_MODE` | `fake` (default se manca **e** il server non ha TLS né `TRUSTED_PROXY`, cioè in sviluppo; con TLS o proxy fidato il default è `real`, così dimenticarlo in produzione non regala sblocchi; il server lo scrive nel log) = accetta **solo** le ricevute del negozio simulato dell'app di debug, nessun pagamento vero — **mai in produzione**. `real` = accetta solo ricevute vere di App Store / Google Play, per le piattaforme configurate qui sotto; le altre (e `fake`) rispondono 503 `platformNotEnabled`. Un valore diverso vale `real`. |
| `APPLE_BUNDLE_ID`, `APPLE_PRODUCT_ID`, `APPLE_ENVIRONMENT` | Con `PAYMENTS_MODE=real`, accendono iOS: bundle id dell'app, ID del prodotto consumabile dello sblocco (lo stesso di `StoreConfig.iosUnlockProductId` nell'app), `sandbox` o `production` (in produzione si accettano anche le transazioni `Sandbox`: App Review compra in sandbox). Bastano queste: la transazione firmata di StoreKit 2 si verifica qui con Apple Root CA - G3, incluso nel codice. |
| `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY_PATH` | Opzionali, tutte e tre insieme: chiave `.p8` "Acquisti in-app" di App Store Connect (Utenti e accesso → Integrazioni). Servono solo per chiedere ad Apple una transazione quando l'app non manda il JWS (App Store Server API, "Get Transaction Info"). Il file `.p8` va tenuto fuori dal repository. |
| `APPLE_ROOT_CA_PATH` | Opzionale: altre radici Apple (`.cer` DER o PEM, separati da virgola) oltre a quella inclusa, se Apple ne introducesse una nuova. |
| `APPLE_NOTIFICATIONS_ENABLED` | `true` = accende `POST /paywall/notifications/apple` (App Store Server Notifications v2: un `REFUND`/`REVOKE` revoca lo sblocco). Senza: 404. |
| `GOOGLE_PACKAGE_NAME`, `GOOGLE_PRODUCT_ID`, `GOOGLE_SERVICE_ACCOUNT_JSON_PATH` | Con `PAYMENTS_MODE=real`, accendono Android: package name, ID del prodotto in-app (lo stesso di `StoreConfig.androidUnlockProductId`), file JSON del service account con accesso alla Google Play Developer API (permessi "Visualizza dati finanziari" e "Gestisci ordini" in Play Console). Tutte e tre obbligatorie: su Android la ricevuta è solo un `purchaseToken` da chiedere a Google. |
| `GOOGLE_RTDN_TOKEN` | Almeno 32 caratteri (`openssl rand -hex 32`): accende `POST /paywall/notifications/google?token=<valore>` (Real-time Developer Notifications via push di Pub/Sub: un acquisto rimborsato/annullato revoca lo sblocco). Senza, o token sbagliato: 404. |
| `PAYMENTS_TRANSACTION_HASH_KEY` | Opzionale, 32 byte in base64: chiave HMAC degli hash delle transazioni riscattate. Senza, una casuale per processo (va benissimo finché il registro è in RAM; serve fissa solo per renderlo persistente). |
| `MODERATION_COOLDOWN_MINUTES` | Dopo una chiusura automatica, per quanti minuti gli IP della sessione chiusa non possono fare nuovi Start (risposta `rateLimited`). Default 30, `0` = spento; un valore non intero è ignorato. |

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

## Segnalazioni e moderazione

Dall'app si può **bloccare** e **segnalare** (che implica bloccare) chi si
vede in "Vicinanze", nelle richieste o nel match (`block`/`report` su `/ws`,
protocollo in `routes/ws.dart`).

- **Blocco** (`BlockStore`): nei due sensi, per tutta la vita della sessione
  di chi blocca (anche attraverso grazia e riconnessioni), sugli id interni.
  Chi è bloccato vede esattamente ciò che vedrebbe se l'altro avesse premuto
  End. Non sopravvive a End/nuovo Start di nessuno dei due: non esistono id
  permanenti.
- **Chiusura automatica** (`ModerationStore`, in RAM): segnalazioni da almeno
  3 sessioni diverse e 2 IP diversi → la sessione segnalata riceve
  `sessionClosed`, viene chiusa (`SessionLifecycle.closeForModeration`) e i
  suoi IP non possono fare nuovi Start per 30 minuti. **IP condivisi**: il
  Wi-Fi di un locale o il CGNAT di un operatore mobile mettono molte persone
  dietro lo stesso IP — durante il cooldown anche loro non possono fare uno
  Start nuovo (le sessioni già aperte non sono toccate); per questo il
  cooldown è breve e regolabile (`MODERATION_COOLDOWN_MINUTES`, `0` lo
  spegne). Dietro un reverse proxy senza `TRUSTED_PROXY` tutti sembrano lo
  stesso IP: la condizione dei 2 IP non scatta mai e il cooldown colpirebbe
  il proxy.
- **Record di moderazione** (`ModerationRecordStore`): l'unico dato che il
  server conserva oltre le sessioni. Uno per sessione segnalata, aggiornato
  a ogni segnalazione: id casuale, selfie della persona segnalata (già senza
  EXIF), motivi con conteggio, numero di segnalazioni, se è scattata la
  chiusura automatica, ora di creazione e aggiornamento arrotondate al
  minuto. **Niente** posizione, chat, id o pseudonimi, profilo, IP (nemmeno
  in hash). Cifrato AES-256-GCM (`MODERATION_KEY`), cancellato 30 giorni dopo
  la creazione (all'avvio e ogni ora) o a mano dopo la revisione.

### Endpoint admin

Solo con `ADMIN_TOKEN`, solo su HTTPS, 120 richieste per IP ogni 10 minuti
(`AdminReportsApi`). `Authorization` non è tra gli header CORS ammessi: non
si chiamano da un browser su un'altra origine.

```
curl -H "Authorization: Bearer $ADMIN_TOKEN" https://host/admin/reports
curl -H "Authorization: Bearer $ADMIN_TOKEN" -o selfie.jpg https://host/admin/reports/<id>/selfie
curl -X DELETE -H "Authorization: Bearer $ADMIN_TOKEN" https://host/admin/reports/<id>
```

La lista risponde `{"recordsEnabled", "retentionDays", "reports": [{"id",
"createdAt", "updatedAt", "expiresAt", "reasons", "reportCount",
"autoClosed", "hasSelfie"}]}`; `DELETE` risponde 204 (segnalazione risolta,
record cancellato) o 404. Codici: 404 spenti o id inesistente/malformato,
429 troppe richieste, 403 senza TLS, 401 token mancante o sbagliato.

## Limiti

| Cosa | Limite | Dove |
|---|---|---|
| Nuovi Start (hello con un segreto nuovo) | 20 per IP ogni 10 minuti (configurabile, `MAX_NEW_SESSIONS_PER_IP`); le riconnessioni non contano | `NewSessionRateLimiter` |
| `POST /paywall/purchase` | 10 per IP ogni 10 minuti; un token **una volta per transazione** verificata (la stessa ridà lo stesso token finché vale, poi 409); acquisti Apple più vecchi di 7 giorni rifiutati (`tooOld`) | `purchaseRateLimiter` in `rate_limiters.dart`, `UnlockPurchaseService` |
| Messaggi per connessione | 20 di fila, poi 5 al secondo; oltre si scartano, dopo 50 scarti di fila il socket si chiude (4029) | `ConnectionRateLimiter` |
| Dimensione di un messaggio | 320 KB `presence`, 16 KB `chatMessage`, 1 KB il resto (oltre, il socket si chiude con 4009) | `RealtimeMessageHandler.maxCharsFor` |
| Selfie | solo JPEG, ≤ ~230 KB, metadati tolti | `SelfieValidator` |
| Testo di chat | 1000 unità UTF-16 (come `SendMessageUseCase` nell'app); oltre → `rejected` `invalidText`, il socket resta aperto. Inoltrato solo con un match attivo | `RealtimeMessageHandler` |
| Richieste d'incontro pendenti | 5 in uscita, 20 in entrata per sessione | `EncounterStore` |
| Spostamenti | oltre 50 m/s (+250 m di tolleranza GPS) la presenza è scartata | `SessionStore.upsertPosition` |
| Posizioni | al più una utile ogni 10 s per sessione; quelle in più sono ignorate in silenzio (`tooSoon`, nessun rifiuto, socket aperto) | `SessionStore.minPositionInterval` |
| Segnalazioni | 5 per sessione di chi segnala (le successive → `rejected` `tooManyReports`, il blocco vale comunque); un doppione verso la stessa persona non conta | `ModerationStore.maxReportsPerSession` |
| Chiusura automatica | 3 sessioni diverse da 2 IP diversi (configurabile); poi cooldown di 30 minuti sui nuovi Start da quegli IP | `ModerationStore`, `SessionLifecycle.hello` |
| Endpoint admin | 120 richieste per IP ogni 10 minuti | `AdminReportsApi` |
| Liste `nearby` | al più una diversa ogni 5 s per osservatore (le modifiche nel frattempo partono alla fine della finestra), oltre al throttle globale di 500 ms | `ConnectionHub.nearbyPushMinInterval` |

## Pagamenti in-app

Lo sblocco di 2 ore si compra solo con gli acquisti in-app (Apple 3.1.1,
Google Play Billing): prodotto **consumabile**. Codice in
`lib/src/payments/`; flusso completo e passi per App Store Connect / Play
Console in [../guida_per_sviluppatori.md](../guida_per_sviluppatori.md)
(§3.6, "Pagamenti in-app").

- **Verifica prima del token**: `ReceiptVerifier` per piattaforma —
  `AppleReceiptVerifier` (JWS di StoreKit 2: firma ES256 e catena `x5c` fino
  ad Apple Root CA - G3, bundle, ambiente, `Consumable`, non rimborsato;
  oppure App Store Server API con le credenziali `.p8`),
  `GooglePlayReceiptVerifier` (`purchases.products.get`, poi
  `purchases.products.consume` dal server), `FakeReceiptVerifier` (solo
  `PAYMENTS_MODE=fake`). Il prodotto deve essere quello configurato, sia
  dichiarato sia firmato.
- **Una volta per transazione** (`UnlockPurchaseService`,
  `RedeemedTransactions`): registro con il solo **HMAC** della transazione,
  la data e il token finché vale; uscita dopo 8 giorni. Un nuovo tentativo
  della stessa transazione riceve lo stesso token (risposta persa); finito lo
  sblocco, 409. Se Google non consuma, il token è revocato e l'app riproverà.
- **Limite al riavvio**: il registro è in RAM. Google non ne risente (la
  transazione è consumata da Google); per Apple, dopo un riavvio, una
  transazione più giovane di 7 giorni potrebbe essere riscattata di nuovo da
  chi l'ha pagata. Per chiuderlo: stesso registro (hash + data, cancellati
  dopo 8 giorni) su disco o database, con `PAYMENTS_TRANSACTION_HASH_KEY`
  fissa.
- **Rimborsi**: route di notifica spente di default (vedi variabili); quando
  accese revocano il token della transazione. URL da configurare:
  `https://<host>/paywall/notifications/apple` (App Store Connect, versione
  2) e `https://<host>/paywall/notifications/google?token=<GOOGLE_RTDN_TOKEN>`
  (sottoscrizione push Pub/Sub).
- **TODO che richiedono gli account**: creare i prodotti, le credenziali
  (`.p8`, service account), configurare le notifiche; facoltativo: OCSP dei
  certificati Apple e autenticazione OIDC di Pub/Sub (commenti `TODO` in
  `apple_jws_verifier.dart` e `store_notifications.dart`).

```
# Prova in locale col negozio simulato (il default)
dart build/bin/server.dart
# Pagamenti veri, sandbox
PAYMENTS_MODE=real APPLE_BUNDLE_ID=com.threemojo.app APPLE_PRODUCT_ID=<id> \
APPLE_ENVIRONMENT=sandbox GOOGLE_PACKAGE_NAME=com.threemojo.app \
GOOGLE_PRODUCT_ID=<id> GOOGLE_SERVICE_ACCOUNT_JSON_PATH=/etc/raen/play.json \
dart build/bin/server.dart
```

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
