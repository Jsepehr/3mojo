# Deploy del server Raen

Server Dart Frog in un container, dietro Caddy che termina TLS. Tutto con
Docker Compose, su una macchina Linux con un dominio che punta a lei.

```
Internet ──443──▶ Caddy (172.28.0.2) ──8080──▶ raen (172.28.0.3)
                  TLS, body ≤ 64 KB,          nessuna porta pubblicata
                  nessun access log           volumi: data, moderation
```

File di questa cartella:

| File | A cosa serve |
|---|---|
| `Dockerfile` | Immagine del server (build da `server/`, `dart_frog build` + `dart compile exe`, Debian slim con le CA di sistema). |
| `docker-compose.yml` | `raen` (rete interna, nessuna porta pubblicata, limite di memoria, restart, volumi, `secrets/` in sola lettura) e `caddy`. |
| `Caddyfile` | `reverse_proxy` con `stream_close_delay`, `request_body max_size 64KB`, **nessun access log**, `/metrics` e `/debug` non esposti. |
| `.env.example` | Tutte le variabili, obbligatorie / consigliate / opzionali, **senza** valori segreti. |

## 1. Prerequisiti

- Docker Engine con il plugin Compose v2 (`docker compose version`).
- Un dominio con il record DNS verso la macchina; porte **80 e 443** aperte
  (Caddy ottiene il certificato da Let's Encrypt da solo).
- Gli account degli store e le loro credenziali (vedi
  `guida_per_sviluppatori.md` §3.6): ID prodotto, chiave `.p8` Apple, service
  account Google.

`dart_frog_cli` **non serve sulla macchina di deploy**: la build lo installa
dentro il container di build. Serve solo per provare il server **in locale**
senza Docker (`dart_frog dev`, `dart_frog build`): in quel caso, una volta, a
mano e sulla propria macchina di sviluppo:

```
dart pub global activate dart_frog_cli
```

## 2. Prima installazione

Dalla cartella `server/deploy/`:

```
# 1. Segreti e configurazione
mkdir -p secrets && chmod 700 secrets
cp /percorso/play-service-account.json secrets/        # Google
cp /percorso/AuthKey_XXXXXXXX.p8 secrets/               # Apple (facoltativo)
chmod 600 secrets/*
cp .env.example .env && chmod 600 .env
openssl rand -base64 32     # -> MODERATION_KEY
openssl rand -base64 32     # -> PAYMENTS_TRANSACTION_HASH_KEY
openssl rand -hex 32        # -> ADMIN_TOKEN
openssl rand -hex 32        # -> GOOGLE_RTDN_TOKEN (se usi le notifiche Google)
openssl rand -hex 32        # -> METRICS_TOKEN
$EDITOR .env                # percorsi dei file: /run/secrets/<nome>

# 2. Build e avvio
docker compose build
docker compose up -d

# 3. Verifica
docker compose ps                                  # raen e caddy "healthy/running"
docker compose logs raen | head -30                # righe JSON: server.started, payments.mode...
curl -fsS https://$RAEN_DOMAIN/                    # {"service":"3mojo","status":"ok"}
docker compose exec raen curl -fsS http://127.0.0.1:8080/metrics   # contatori
```

Con `RAEN_ENV=production` (fissato dal compose) il server **non parte** se manca
una difesa: `PAYMENTS_MODE=real`, `MODERATION_KEY` valida, `ADMIN_TOKEN` ≥ 32
caratteri, `PAYMENTS_TRANSACTION_HASH_KEY` fissa, e nessuno tra
`DEBUG_ENDPOINTS_TOKEN`, `ADMIN_ALLOW_INSECURE_HTTP`, `ATTESTATION_ALLOW_FAKE`.
Se `docker compose ps` mostra `raen` che si riavvia in loop, `docker compose logs
raen` dice quale controllo è fallito.

Poi, nell'app: `--dart-define=API_BASE_URL=https://$RAEN_DOMAIN` (e le altre
define in `lib/core/config/`).

### Notifiche degli store

- Apple: App Store Connect → URL delle notifiche (versione 2):
  `https://$RAEN_DOMAIN/paywall/notifications/apple`.
- Google: sottoscrizione push di Pub/Sub verso
  `https://$RAEN_DOMAIN/paywall/notifications/google?token=<GOOGLE_RTDN_TOKEN>`.
  Per questo Caddy **non scrive access log**: il token è nell'URL.

## 3. Cosa si conserva, dove

| Volume | Contenuto | Durata | Backup |
|---|---|---|---|
| `raen_data` (`DATA_DIR`) | `unlocks.state`: SHA-256 dei token di sblocco (2 ore) e HMAC delle transazioni (8 giorni), cifrato, `600`. Nessun dato personale. | 2 ore / 8 giorni | Utile, non critico: senza, un riavvio fa perdere gli sblocchi in corso e riapre il doppio riscatto Apple per le transazioni più giovani di 7 giorni. |
| `raen_moderation` (`MODERATION_DIR`) | Record di moderazione cifrati (selfie segnalato, motivi). | 30 giorni | Solo con la `MODERATION_KEY` (tenuta altrove): senza, i file non si leggono. |

Tutto il resto (sessioni, posizioni, chat inoltrata, richieste, blocchi) è in
RAM e sparisce a ogni riavvio, per progetto.

**Chiavi**: cambiare `PAYMENTS_TRANSACTION_HASH_KEY` rende illeggibile
`unlocks.state` (il server lo scrive nel log e riparte da vuoto: stesso effetto
di un file perso); cambiare `MODERATION_KEY` rende illeggibili i record vecchi
(spariscono comunque entro 30 giorni). Non vanno ruotate alla leggera; vanno
custodite in un gestore di segreti, fuori dal repository.

## 4. Deploy notturno (aggiornamento del server)

Un riavvio **chiude tutte le sessioni online** (stato in RAM): chi è collegato
riceve `sessionClosed` `serverRestart`, vede "Server in riavvio" e rifà Start.
Gli **sblocchi pagati e le transazioni sopravvivono** (`DATA_DIR`). Per questo
si fa di notte, quando c'è meno gente.

Prima (di giorno, senza fermare nulla):

```
cd server && git pull
docker tag raen-server:latest raen-server:previous        # per il rollback
cd deploy
docker compose build raen                                  # l'immagine nuova, il vecchio gira ancora
```

Nella finestra notturna:

```
docker compose up -d --no-deps raen
# Compose manda SIGTERM al vecchio container: niente nuove connessioni,
# sessionClosed/serverRestart ai client, socket chiusi con 1012, salvataggio
# dello stato, uscita entro ~5 s (stop_grace_period 10 s); parte il nuovo.
docker compose ps
docker compose logs --since 2m raen        # shutdown.done (vecchio), state.restored + server.started (nuovo)
docker compose exec raen curl -fsS http://127.0.0.1:8080/metrics
```

Controlli dopo il deploy:

- `server.started` e `state.restored` (`unlocks`/`transactions` ≠ 0 se c'erano
  acquisti nelle ultime ore/giorni) nel log;
- le `connections.accepted` di `/metrics` crescono (i client si riconnettono);
- nessun `level":"error"` ripetuto; `moderationRecords.failed` a 0.

**Rollback**:

```
docker tag raen-server:previous raen-server:latest
docker compose up -d --no-deps raen
```

Se la nuova versione **cambia il protocollo** (`ProtocolPolicy.currentVersion`
in `server/lib/src/protocol_version.dart`): il server accetta N e N-1, quindi
prima si pubblica l'app nuova, si aspetta che si diffonda, e solo dopo si alza
il minimo (`MIN_PROTOCOL_VERSION`) per far aggiornare le app vecchie.

## 5. Limiti da tenere anche nel proxy

Il server si difende da solo, ma la prima linea è il proxy. Con Caddy sono già
nel `Caddyfile`; con un altro proxy (nginx, load balancer del provider) vanno
rifatti:

| Limite | Valore | Perché |
|---|---|---|
| Corpo delle richieste HTTP | **64 KB** (`request_body max_size`) | È anche il tetto del server (`maxHttpBodyBytes`); la richiesta più grande è una transazione firmata di Apple. |
| Tempo di attesa dell'upstream | connessione 5 s, prima risposta 30 s | Un backend lento non tiene appese le richieste. |
| WebSocket | nessun timeout di inattività sotto **90 s**; keepalive del proxy ≥ 25 s | L'app manda un ping ogni 20 s e il server chiude i silenzi da 90 s. Un `proxy_read_timeout` di 60 s (nginx) spezzerebbe i socket quieti. |
| Reload della configurazione | `stream_close_delay` (Caddy) / `worker_shutdown_timeout` (nginx) | Senza, ogni reload chiude tutte le sessioni. |
| Header | `X-Forwarded-For` (client in coda) e `X-Forwarded-Proto` aggiunti dal proxy; `TRUSTED_PROXY` = l'indirizzo del proxy | Senza `TRUSTED_PROXY` tutti i client hanno lo stesso IP e i limiti per IP colpiscono tutti. |
| Percorsi non esposti | `/metrics`, `/debug` | Solo rete interna; `/admin/reports` ammesso (token + TLS). |
| Access log | **spento** | `?token=` di `POST /paywall/notifications/google` e, più in generale, niente URL nei log. |
| Connessioni per IP | consigliato ~50 (es. `limit_conn` in nginx, plugin rate-limit in Caddy) | Il server ha solo il tetto globale `MAX_WS_CONNECTIONS` (default 2000) e i limiti sui nuovi Start per IP (`MAX_NEW_SESSIONS_PER_IP`). Il Wi-Fi di un locale ha molte persone dietro un IP: non scendere troppo. |
| Rate limit generico | consigliato sul proxy (es. 10 richieste/s per IP su `/paywall/*`) | Oltre ai 10 acquisti per IP ogni 10 minuti del server. |

## 6. Comandi utili

```
docker compose logs -f raen                     # log JSON, una riga per evento, senza IP/token
docker compose logs raen | grep '"level":"error"'
docker compose exec raen curl -s http://127.0.0.1:8080/metrics | python3 -m json.tool
curl -H "Authorization: Bearer $METRICS_TOKEN" http://172.28.0.3:8080/metrics   # da un altro container sulla rete
docker compose restart raen                      # riavvio ordinato (come un deploy)
docker compose down                              # ferma tutto (i volumi restano)
```
