# threemojo_server

[![style: dart frog lint][dart_frog_lint_badge]][dart_frog_lint_link]
[![License: MIT][license_badge]][license_link]
[![Powered by Dart Frog](https://img.shields.io/endpoint?url=https://tinyurl.com/dartfrog-badge)](https://dart-frog.dev)

Backend [Dart Frog](https://dart-frog.dev) dell'app **Raen** (`threemojo_app`,
nella cartella superiore). Tiene **solo in RAM** tutto lo stato di sessione
(sessioni, richieste d'incontro, chat inoltrate, blocchi, segnalazioni,
hotspot): riavviarlo lo cancella. **Due eccezioni su disco, entrambe cifrate**:
i record di moderazione (vedi [Segnalazioni e
moderazione](#segnalazioni-e-moderazione), 30 giorni) e lo stato degli
acquisti — solo hash degli sblocchi (2 ore) e delle transazioni riscattate
(8 giorni), vedi [Stato degli acquisti](#stato-degli-acquisti-su-disco). Architettura e regole sono
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

`dart_frog_cli` non è una dipendenza del progetto: per provare il server in
locale va installata a mano, una volta, sulla propria macchina (`dart pub
global activate dart_frog_cli`). In produzione non serve: l'immagine Docker la
installa solo nello stadio di build (vedi [deploy/README.md](deploy/README.md),
che spiega anche Caddy, i volumi, il deploy notturno e il rollback).

`pubspec.lock` è **committato**: le build (e l'immagine Docker) usano le versioni
provate.

Route: `GET /` (controllo di salute), `GET /metrics` (solo loopback o
`METRICS_TOKEN`, vedi [Log e metriche](#log-e-metriche)), `GET /ws` (WebSocket), `POST
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
| `RAEN_ENV` | `production` = **fail closed**: il server NON parte se `PAYMENTS_MODE` non è `real`, se `MODERATION_KEY` manca o non è valida, se `ADMIN_TOKEN` ha meno di 32 caratteri o manca, se manca `PAYMENTS_TRANSACTION_HASH_KEY` (fissa, 32 byte in base64), o se sono impostati `DEBUG_ENDPOINTS_TOKEN`, `ADMIN_ALLOW_INSECURE_HTTP` (diverso da `false`) o `ATTESTATION_ALLOW_FAKE`; tutti i motivi insieme nel messaggio d'errore. In production anche il CORS è spento (vedi `CORS_ALLOW_ORIGIN`). `development` o vuoto = i default da sviluppo. Qualsiasi altro valore (un refuso: `prod`) rifiuta l'avvio. Vale **sempre**, anche senza `RAEN_ENV`: `PAYMENTS_MODE=fake` esplicito con `TLS_CERT_PATH` o `TRUSTED_PROXY` rifiuta l'avvio. |
| `DATA_DIR` | Cartella dello stato degli acquisti (`unlocks.state`, cifrato, `600`, dentro una cartella `700`). Default `data` nella cartella di lavoro (nell'immagine Docker `/var/lib/raen/data`, un volume). Usata solo con `PAYMENTS_TRANSACTION_HASH_KEY` impostata. |
| `MAX_WS_CONNECTIONS` | Tetto alle connessioni WebSocket aperte insieme (default 2000): oltre, `GET /ws` risponde 503 `Retry-After` prima dell'upgrade. Tarare sul limite di memoria (ogni sessione porta un selfie fino a ~230 KB). |
| `MIN_PROTOCOL_VERSION` | Alza il minimo del protocollo accettato (default: N-1, vedi [Versione del protocollo](#versione-del-protocollo)); mai oltre la versione attuale. I client sotto il minimo ricevono `updateRequired`. |
| `METRICS_TOKEN` | Almeno 32 caratteri: abilita `GET /metrics` anche da fuori loopback (`Authorization: Bearer <token>`). Senza, solo da loopback diretto. |
| `CORS_ALLOW_ORIGIN` | Origini ammesse dal CORS, separate da virgola (`https://app.example`), `*` o `none`. Default: `*` in sviluppo, **nessun header CORS** con `RAEN_ENV=production` (le app Android/iOS non ne hanno bisogno; serve solo a `flutter run -d chrome`). |
| `LOG_LEVEL` | `debug`, `info` (default), `warn`, `error`. |
| `TLS_CERT_PATH` + `TLS_KEY_PATH` | Percorsi di catena di certificati e chiave privata (PEM). Se presenti entrambe il server parla **solo** `https://`/`wss://` (vedi `main.dart`). Con una sola delle due si rifiuta di partire. |
| `DEBUG_ENDPOINTS_TOKEN` | Accende `GET /debug/sessions`, che risponde solo con l'header `X-Debug-Token` uguale a questo valore. Senza, l'endpoint risponde 404. Da non impostare in produzione. Non espone posizioni né distanze tra persone. |
| `MAX_NEW_SESSIONS_PER_IP` | Quanti nuovi Start (hello con un segreto nuovo) ammette lo stesso IP ogni 10 minuti (`NewSessionRateLimiter`). Default 20; un valore non intero o ≤ 0 è ignorato. Da alzare solo per le prove in locale (es. `200` col simulatore, che da solo apre 20 sessioni). |
| `TRUSTED_PROXY` | IP dei reverse proxy fidati, separati da virgola (es. `127.0.0.1,10.0.0.5`). Solo per le connessioni che arrivano da uno di questi si legge `X-Forwarded-For` per i limiti per IP (nuovi Start su `/ws`, `POST /paywall/purchase`). Gli indirizzi sono normalizzati: `::ffff:127.0.0.1` e `127.0.0.1` sono lo stesso proxy. Vuoto = l'header è ignorato (chiunque potrebbe falsificarlo). Dietro un proxy **va impostato**, altrimenti tutti i client sembrano lo stesso IP. |
| `MODERATION_KEY` | Chiave AES-256-GCM dei record di moderazione: 32 byte in base64, es. `openssl rand -base64 32`. **Senza (o non valida) i record non vengono salvati** e il server lo scrive nel log all'avvio; blocchi, soglie e chiusura automatica funzionano lo stesso. Tenerla fuori dal repository e dai backup dei record: chi ha i file senza la chiave non legge nulla. Cambiarla rende illeggibili i record vecchi (spariscono comunque entro 30 giorni dalla data del file). |
| `MODERATION_DIR` | Cartella dei record (un file `<id>.rec` per record). Default `moderation_records` nella cartella di lavoro. Creata con permessi `700` dove possibile; va su un disco non condiviso. |
| `ADMIN_TOKEN` | Accende gli endpoint `/admin/reports` (header `Authorization: Bearer <token>`, confronto a tempo costante). Almeno 32 caratteri (es. `openssl rand -hex 32`), altrimenti restano spenti (404) e il server lo scrive nel log. |
| `ADMIN_ALLOW_INSECURE_HTTP` | `true` = gli endpoint admin rispondono anche in chiaro, **solo** a connessioni da loopback (sviluppo locale). In ogni altro caso servono TLS diretto (`TLS_*`) o un proxy fidato (`TRUSTED_PROXY`) che mandi `X-Forwarded-Proto: https`, altrimenti 403. |
| `MODERATION_AUTO_CLOSE_REPORTS` | Da quante sessioni diverse deve essere segnalata una sessione per essere chiusa da sola. Default 3. |
| `MODERATION_AUTO_CLOSE_MIN_IPS` | Da quanti IP diversi devono arrivare quelle segnalazioni. Default 2 (se nessun segnalatore ha un IP noto, la condizione è ignorata). |
| `PAYMENTS_MODE` | `fake` (default se manca **e** il server non ha TLS né `TRUSTED_PROXY`, cioè in sviluppo; con TLS o proxy fidato il default è `real`, così dimenticarlo in produzione non regala sblocchi; il server lo scrive nel log) = accetta **solo** le ricevute del negozio simulato dell'app di debug, nessun pagamento vero — **mai in produzione**. `real` = accetta solo ricevute vere di App Store / Google Play, per le piattaforme configurate qui sotto; le altre (e `fake`) rispondono 503 `platformNotEnabled`. Un valore diverso vale `real`. |
| `PAYWALL_MODE` | `paid` (default, anche se manca o è scritto male: un refuso non regala mai le foto, e il server lo scrive nel log) = il paywall di sempre: un terzo delle persone più lontane è gratis, le altre arrivano `locked` e senza foto finché non c'è uno sblocco valido. `free` = **tutto gratis**: nessuna persona arriva `locked`, chiunque vede ogni foto, per i primi mesi dopo il lancio. Cambia solo cosa vede chi guarda: acquisti, token e scadenze restano quelli di sempre, e le app non cambiano (il blocco lo decide solo il server). Per tornare a pagamento: togliere la variabile (o `paid`) e riavviare, di notte come ogni riavvio. Non dipende da `PAYMENTS_MODE`. |
| `APPLE_BUNDLE_ID`, `APPLE_PRODUCT_ID`, `APPLE_ENVIRONMENT` | Con `PAYMENTS_MODE=real`, accendono iOS: bundle id dell'app, ID del prodotto consumabile dello sblocco (lo stesso di `StoreConfig.iosUnlockProductId` nell'app), `sandbox` o `production` (in produzione si accettano anche le transazioni `Sandbox`: App Review compra in sandbox). Bastano queste: la transazione firmata di StoreKit 2 si verifica qui con Apple Root CA - G3, incluso nel codice. |
| `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY_PATH` | Opzionali, tutte e tre insieme: chiave `.p8` "Acquisti in-app" di App Store Connect (Utenti e accesso → Integrazioni). Servono solo per chiedere ad Apple una transazione quando l'app non manda il JWS (App Store Server API, "Get Transaction Info"). Il file `.p8` va tenuto fuori dal repository. |
| `APPLE_ROOT_CA_PATH` | Opzionale: altre radici Apple (`.cer` DER o PEM, separati da virgola) oltre a quella inclusa, se Apple ne introducesse una nuova. |
| `APPLE_NOTIFICATIONS_ENABLED` | `true` = accende `POST /paywall/notifications/apple` (App Store Server Notifications v2: un `REFUND`/`REVOKE` revoca lo sblocco). Senza: 404. |
| `GOOGLE_PACKAGE_NAME`, `GOOGLE_PRODUCT_ID`, `GOOGLE_SERVICE_ACCOUNT_JSON_PATH` | Con `PAYMENTS_MODE=real`, accendono Android: package name, ID del prodotto in-app (lo stesso di `StoreConfig.androidUnlockProductId`), file JSON del service account con accesso alla Google Play Developer API (permessi "Visualizza dati finanziari" e "Gestisci ordini" in Play Console). Tutte e tre obbligatorie: su Android la ricevuta è solo un `purchaseToken` da chiedere a Google. |
| `GOOGLE_RTDN_TOKEN` | Almeno 32 caratteri (`openssl rand -hex 32`): accende `POST /paywall/notifications/google?token=<valore>` (Real-time Developer Notifications via push di Pub/Sub: un acquisto rimborsato/annullato revoca lo sblocco). Senza, o token sbagliato: 404. |
| `PAYMENTS_TRANSACTION_HASH_KEY` | 32 byte in base64 (`openssl rand -base64 32`): chiave HMAC degli hash delle transazioni riscattate **e** (derivata) chiave di cifratura di `unlocks.state`. **Obbligatoria in production.** Senza (solo sviluppo) ne esce una casuale per processo e lo stato resta in RAM, senza persistenza. Cambiarla rende illeggibile il file (il server lo scrive nel log e riparte da vuoto). |
| `MODERATION_COOLDOWN_MINUTES` | Dopo una chiusura automatica, per quanti minuti gli IP della sessione chiusa non possono fare nuovi Start (risposta `rateLimited`). Default 30, `0` = spento; un valore non intero è ignorato. |
| `ATTESTATION_MODE` | Verifica del dispositivo (App Attest / Play Integrity) per le sessioni **nuove**, vedi [sotto](#verifica-del-dispositivo). `off` (default) = nessun challenge, protocollo invariato. `log` = challenge e verifica, esito solo nel log (`[attestazione] …`), nessun rifiuto. `enforce` = senza attestazione valida `error` `attestationRequired` e chiusura 4011. Un valore diverso, o `enforce` senza **entrambe** le piattaforme configurate, e il server **non parte** (mai un rifiuto silenzioso di tutti, mai una piattaforma lasciata aperta). |
| `GOOGLE_PACKAGE_NAME` + `PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_PATH` | Con `ATTESTATION_MODE` `log`/`enforce`, accendono la verifica Android (Play Integrity, `decodeIntegrityToken`). Il service account deve stare nel progetto Google Cloud **collegato all'app in Play Console** con la Play Integrity API abilitata. Senza `PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_PATH` si usa `GOOGLE_SERVICE_ACCOUNT_JSON_PATH` dei pagamenti. Il numero del progetto Google Cloud serve solo all'app (`--dart-define=GOOGLE_CLOUD_PROJECT_NUMBER`), non al server. |
| `APPLE_TEAM_ID`, `APPLE_BUNDLE_ID`, `APPLE_APP_ATTEST_ENVIRONMENT` | Con `ATTESTATION_MODE` `log`/`enforce`, accendono la verifica iOS (App Attest): Team ID (10 caratteri), bundle id (lo stesso dei pagamenti), `development` o `production` — deve corrispondere all'entitlement dell'app (`ios/Runner/Runner.entitlements`, oggi `production`; App Store e TestFlight usano sempre `production`). La radice Apple App Attestation Root CA è inclusa nel codice. |
| `ATTESTATION_MAX_PER_IP_PER_MINUTE` | Quante attestazioni si verificano per IP al minuto (default 10; oltre: `rateLimited`, in `log` solo non verificate). |
| `ATTESTATION_ALLOW_FAKE` | `true` = accetta l'attestazione **finta** dei build di debug (`platform: "fake"`), per provare `log`/`enforce` in locale. Ignorato (e scritto nel log) se il server ha TLS o `TRUSTED_PROXY`. Con questa, `enforce` parte anche senza Apple/Google. **Mai in produzione.** |

Senza `TLS_*` il server resta in chiaro: va bene in sviluppo locale, in
produzione **solo** dietro un reverse proxy che termina TLS (vedi
[deploy/](deploy/README.md)). L'app in release
accetta comunque solo `API_BASE_URL=https://…`.

## WebSocket `/ws`

Il protocollo completo (messaggi e campi) è documentato in testa a
`routes/ws.dart`: quella è la fonte di verità.

### Versione del protocollo

L'`hello` porta `"protocol": 1` (e `"appVersion"`, solo informativa); `welcome`
risponde con `"protocol"`. **Politica** (`ProtocolPolicy`): il server accetta la
versione attuale N e la precedente N-1, così un rilascio graduale non rompe
nessuno; assente vale 0 (le app uscite prima del meccanismo). Una versione
troppo vecchia riceve `{"type":"error","code":"updateRequired","minProtocol":…,
"protocol":…}` e il socket si chiude con **4012**, prima di ogni altro controllo
(nessun Start contato); il client lo tratta come definitivo (nessuna
riconnessione automatica) e invita ad aggiornare. Una versione più nuova è
accettata. Le rotte `/paywall/*` leggono l'header `X-Raen-Protocol` (assente = 0)
e rispondono **426** `{"code":"updateRequired"}` sotto il minimo (con lo stesso
header, valorizzato con la versione attuale).

**Regola di compatibilità**: client e server ignorano campi e tipi di messaggio
sconosciuti. Si aggiungono campi e messaggi senza alzare la versione; la si alza
(e con essa `ProtocolPolicy.currentVersion` e `ProtocolConfig.version` nell'app)
solo cambiando il *significato* di qualcosa che esiste. Oggi N = 1, minimo 0: passano
tutti. `MIN_PROTOCOL_VERSION` forza l'aggiornamento senza toccare il codice.

Cambi compatibili già fatti senza alzare la versione: il campo `place` (luogo,
lista chiusa; mancante o sconosciuto → `other`) al posto di `intent`
(`otherPlace` nelle richieste), la proposta `dance` (un server vecchio la legge
come `getToKnow`) e un sì che non cancella più le altre richieste pendenti (solo
meno messaggi `cancelled`; un sì in match → `rejected` `inMatch`).

### Spegnimento ordinato

Con SIGTERM o SIGINT (`docker stop`, deploy): smette di accettare connessioni,
manda a ogni client `{"type":"sessionClosed","reason":"serverRestart"}`, chiude i
socket con **1012**, aspetta i salvataggi (stato degli acquisti, record di
moderazione) ed esce, in ogni caso entro ~5 s (`GracefulShutdown`). Lo stato di
sessione sparisce (è in RAM): per i client è una sessione chiusa dal server — End,
nessuna riconnessione, avviso "Server in riavvio" — e rifanno Start. Nessun
cooldown. Sblocchi e transazioni sopravvivono (`DATA_DIR`).

**Autenticazione**: il segreto di sessione arriva col **primo messaggio**
(`{"type":"hello","secret":...}`, entro 10 s), mai nell'URL. Il server lo
traduce in un id interno casuale (`SessionCredentials`) che non esce mai dal
server, e risponde `welcome` oppure `error` (`invalidSecret`/`rateLimited`)
chiudendo il socket. Con la verifica del dispositivo accesa
(`ATTESTATION_MODE`), un hello che aprirebbe una sessione **nuova** riceve prima
un `challenge` (vedi [sotto](#verifica-del-dispositivo)). Agli altri utenti arrivano solo **pseudonimi per
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

**Selfie nelle liste e nelle richieste**: il selfie di una persona nella lista
`nearby` parte **una volta per pseudonimo e per socket** (in un locale pieno
erano fino a ~12 MB a ogni lista); le liste successive omettono `selfieBase64` e
il client riusa quello ricevuto per lo stesso `personId` (cache azzerata a End;
un nuovo socket li riceve di nuovo, e una persona dietro il paywall la prima
volta che è sbloccata). Lo snapshot `encounters` fa lo stesso per richiesta.

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

## Verifica del dispositivo

Predisposta e **spenta** (`ATTESTATION_MODE=off`). Serve a rendere costose le
sessioni parallele da script — usate per ricostruire le preferenze altrui
rifacendo Start con generi diversi, o per localizzare qualcuno con GPS falsi
da più punti: ogni sessione **nuova** deve venire dall'app vera su un
dispositivo vero.

```
client                                server
  hello {secret}  ───────────────────▶  sessione nuova? (non una riconnessione)
                  ◀───────────────────  challenge {nonce, expiresInSeconds: 20}
  App Attest / Play Integrity
  legati al nonce
  attestation {platform, …}  ────────▶  AttestationGate: verifica (Apple/Google)
                  ◀───────────────────  welcome  |  error attestationRequired (4011)
```

- **Challenge nel socket**, non un `GET /attest/challenge`: il nonce (32 byte
  casuali) vive solo nel `SocketSession` che l'ha emesso, vale una volta e
  per 20 s; un'attestazione fatta per un socket non vale su un altro e non
  serve nessuna tabella di nonce condivisa. Lo manda il server **dopo**
  l'hello perché solo lui sa se è una sessione nuova o una riconnessione
  (che non si riattesta: niente costo per ogni caduta di rete). Con `off`
  non arriva mai: protocollo identico a prima.
- **Android** (`PlayIntegrityVerifier`): Standard API, `requestHash =
  hex(SHA-256(utf8(nonce)))`; si controllano package, `requestHash`, età del
  verdetto (≤ 2 min), `PLAY_RECOGNIZED`, `MEETS_DEVICE_INTEGRITY`.
- **iOS** (`AppAttestVerifier`): una **chiave nuova a ogni sessione**,
  attestata con `clientDataHash = SHA-256(utf8(nonce))`; catena `x5c` fino ad
  Apple App Attestation Root CA (inclusa, impronta SHA-256
  `1cb9823b…6242c932`), nonce nell'estensione `1.2.840.113635.100.8.2`, RP ID
  hash di `APPLE_TEAM_ID.APPLE_BUNDLE_ID`, contatore 0, AAGUID dell'ambiente,
  `keyId`. **Niente assertion**: richiederebbero di ricordare la chiave tra
  una sessione e l'altra, cioè un id stabile del dispositivo.
- **Privacy**: nessun dato dell'attestazione viene salvato (token, keyId,
  receipt, verdetto vivono solo durante la verifica); in RAM restano i
  contatori per esito e, per un minuto, gli orari delle attestazioni per IP.
  Il log scrive solo modalità, piattaforma, esito e motivo — mai IP, token,
  nonce o keyId.
- **`enforce` è fail closed**: anche "Google non risponde" (rete, quota
  esaurita, credenziali) è un rifiuto, altrimenti esaurire la nostra quota
  aprirebbe la porta a tutti. L'app non riprova da sola dopo un rifiuto
  (Riprova o End).
- **Metriche** per passare da `log` a `enforce`: ogni esito finisce nel log
  con i totali da quando il server è partito (`valid`, `invalid` col motivo,
  `missing`, `timeout`, `unavailable`, `unsupportedPlatform`, `rateLimited`,
  `expiredChallenge`). Passi completi in `guida_per_sviluppatori.md` ("Per
  attivare la verifica del dispositivo").

```
# Prova in locale del giro completo con l'app di debug (attestazione finta)
ATTESTATION_MODE=enforce ATTESTATION_ALLOW_FAKE=true dart_frog dev
```

## Limiti

| Cosa | Limite | Dove |
|---|---|---|
| Nuovi Start (hello con un segreto nuovo) | 20 per IP ogni 10 minuti (configurabile, `MAX_NEW_SESSIONS_PER_IP`); le riconnessioni non contano | `NewSessionRateLimiter` |
| `POST /paywall/purchase` | 10 per IP ogni 10 minuti; un token **una volta per transazione** verificata (la stessa ridà lo stesso token finché vale, poi 409); acquisti Apple più vecchi di 7 giorni rifiutati (`tooOld`) | `purchaseRateLimiter` in `rate_limiters.dart`, `UnlockPurchaseService` |
| Messaggi per connessione | 20 di fila, poi 5 al secondo; oltre si scartano, dopo 50 scarti di fila il socket si chiude (4029) | `ConnectionRateLimiter` |
| Dimensione di un messaggio | 320 KB `presence`, 40 KB `attestation`, 16 KB `chatMessage`, 1 KB il resto (oltre, il socket si chiude con 4009) | `RealtimeMessageHandler.maxCharsFor` |
| Verifica del dispositivo | risposta al `challenge` entro 25 s (nonce valido 20 s, una volta); 10 attestazioni verificate per IP al minuto (`ATTESTATION_MAX_PER_IP_PER_MINUTE`); al più 32 verifiche in corso, 10 s ciascuna | `SocketSession`, `AttestationGate` |
| Selfie | solo JPEG, ≤ ~230 KB, metadati tolti | `SelfieValidator` |
| Testo di chat | 1000 unità UTF-16 (come `SendMessageUseCase` nell'app); oltre → `rejected` `invalidText`, il socket resta aperto. Inoltrato solo con un match attivo | `RealtimeMessageHandler` |
| Richieste d'incontro pendenti | 5 in uscita, 20 in entrata per sessione | `EncounterStore` |
| Spostamenti | oltre 50 m/s (+250 m di tolleranza GPS) la presenza è scartata | `SessionStore.upsertPosition` |
| Posizioni | al più una utile ogni 10 s per sessione; quelle in più sono ignorate in silenzio (`tooSoon`, nessun rifiuto, socket aperto) | `SessionStore.minPositionInterval` |
| Segnalazioni | 5 per sessione di chi segnala (le successive → `rejected` `tooManyReports`, il blocco vale comunque); un doppione verso la stessa persona non conta | `ModerationStore.maxReportsPerSession` |
| Chiusura automatica | 3 sessioni diverse da 2 IP diversi (configurabile); poi cooldown di 30 minuti sui nuovi Start da quegli IP | `ModerationStore`, `SessionLifecycle.hello` |
| Endpoint admin | 120 richieste per IP ogni 10 minuti | `AdminReportsApi` |
| Corpo delle richieste HTTP | 64 KB (4 KB per `/paywall/status`); oltre → 413 | `readJsonBody` (`http_limits.dart`) |
| Connessioni WebSocket aperte | 2000 insieme (`MAX_WS_CONNECTIONS`); oltre → 503 `Retry-After` prima dell'upgrade | `WebSocketConnectionLimit` |
| Protocollo | versione N e N-1 (`MIN_PROTOCOL_VERSION` per alzare il minimo); sotto → `updateRequired` + 4012 / 426 | `ProtocolPolicy` |
| Permessi dei file | file `600` (temporaneo ristretto prima di scriverci), cartelle `700` | `secure_file.dart` |

**Da mettere anche nel reverse proxy** (prima linea di difesa, valori e
motivi in [deploy/README.md §5](deploy/README.md)): corpo massimo 64 KB, timeout
di connessione/risposta all'upstream, nessun timeout di inattività sotto 90 s per i
WebSocket (il client manda un ping ogni 20 s), un tetto di connessioni per IP
(~50, senza esagerare: un locale ha molte persone dietro lo stesso IP), un rate
limit generico su `/paywall/*`, `/metrics` e `/debug` non esposti, **nessun
access log** (il token RTDN di Google è in query string).
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
- **Riavvii**: sblocchi e registro **sopravvivono** (vedi [Stato degli
  acquisti](#stato-degli-acquisti-su-disco)): il doppio riscatto di una
  transazione Apple dopo un riavvio non è più possibile. Limite residuo: dopo un
  riavvio il token in chiaro non c'è più (su disco c'è solo l'hash), quindi un
  *nuovo tentativo* della stessa transazione riceve 409 invece dello stesso
  token; lo sblocco già in mano al client resta valido.
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
PAYMENTS_MODE=real APPLE_BUNDLE_ID=com.raen.app APPLE_PRODUCT_ID=<id> \
APPLE_ENVIRONMENT=sandbox GOOGLE_PACKAGE_NAME=com.raen.app \
GOOGLE_PRODUCT_ID=<id> GOOGLE_SERVICE_ACCOUNT_JSON_PATH=/etc/raen/play.json \
dart build/bin/server.dart
```

### Stato degli acquisti su disco

`DATA_DIR/unlocks.state` (`UnlockStateStore`, `UnlockStatePersistence`): **un
file**, cifrato AES-256-GCM con una chiave derivata da
`PAYMENTS_TRANSACTION_HASH_KEY`, scritto in modo atomico (temporaneo + `rename`)
con permessi `600` in una cartella `700`. Contiene **solo**:

- SHA-256 del token di sblocco → ora dello sblocco, finché vale (2 ore);
- HMAC della transazione → data del riscatto e SHA-256 del suo token, per 8 giorni.

Mai token o transazioni in chiaro, mai dati personali. Si rimette in RAM
all'avvio (`state.restored` nel log), si riscrive a ogni cambiamento (scritture
serializzate e raggruppate; il riscatto di un acquisto aspetta che sia su disco
prima di rispondere e di consumare l'acquisto su Google) e si ripulisce a ogni
salvataggio e ogni ora. Un file illeggibile (chiave cambiata, rovinato) non ferma
il server: log `state.restore_failed`, ripartenza da vuoto, file sovrascritto. Un
disco che fallisce non fa fallire l'acquisto: `state.save_failed` nel log e si
continua in RAM — **da monitorare** (`/metrics` non lo conta: grep sul log).

**Perché un file e non SQLite**: poche righe al giorno e un solo processo; nessuna
libreria nativa da portare nell'immagine Docker, niente file `-wal`/`-shm`, niente
problemi di versione; l'atomicità la dà `rename`. L'interfaccia è `load`/`save`:
se un giorno servissero più processi o migliaia di acquisti al giorno, si
sostituisce senza toccare il resto.

## Log e metriche

Un solo logger (`Log`, `lib/src/log.dart`): **una riga JSON per evento su stderr**,
`{"t","level","event",…}`, livello da `LOG_LEVEL`. Mai IP, posizione, pseudonimi,
segreti o token: i campi sono solo numeri/booleani/stringhe brevi, ogni stringa
passa da `Log.scrub` (che cancella ciò che somiglia a un IP o a un token) e di
un errore si scrive il **tipo**, mai il messaggio. Eventi principali:
`server.started`, `payments.mode`, `payments.rejected`, `state.restored`,
`state.save_failed`, `moderation.save_failed`, `ws.message_unhandled`,
`shutdown.start`/`shutdown.done`.

`GET /metrics` (`MetricsApi`): JSON con contatori **aggregati**: `sessions`
(connesse, in grazia, sblocchi attivi, connessioni WebSocket), `connections`
(accettate/rifiutate), `messages` per tipo, `rejected` per motivo, `purchases` per
esito, `attestations` per esito, `moderationRecords` (saved/failed), `rssBytes`,
`uptimeSeconds`. Si legge **solo** da loopback diretto (una richiesta che porta
`X-Forwarded-For` non conta come locale: un proxy sullo stesso host farebbe
sembrare locale tutta Internet) o con `Authorization: Bearer <METRICS_TOKEN>`;
altrimenti 404. Il Caddyfile di `deploy/` non lo espone all'esterno.

## Simulatore di dispositivi

```
dart run tool/simulate_fake_devices.dart [wsBaseUrl]   # default ws://localhost:8080
```

Col server già acceso, apre 20 connessioni WebSocket vere (stesso protocollo
dell'app: `hello`, `presence` ogni 20 s dopo il `welcome`, `end` alla
chiusura; al `challenge` risponde con l'attestazione finta, che in `enforce`
passa solo con `ATTESTATION_ALLOW_FAKE=true`) disposte per far
vedere visibilità normale e hotspot (che si formano dopo 15 minuti). Dettagli
nel commento del file. Venti Start dallo stesso IP sono esattamente il tetto
di `NewSessionRateLimiter`: rilanciarlo entro 10 minuti può essere rifiutato
(`rateLimited`), e il simulatore lo ricorda all'avvio. Per le prove avvia il
server con `MAX_NEW_SESSIONS_PER_IP=200`.

## Test

```
dart test
```
