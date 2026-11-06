# Guida: mettere online il primo server Lemani

Guida passo per passo per un **server vero** (VPS + dominio + HTTPS) con cui provare l'app
fuori dal Wi-Fi di casa. Il server è già pronto in [`server/deploy/`](../server/deploy/)
(Docker, Caddy con certificato automatico, avvio con controlli di sicurezza): qui ci sono solo
i passi da fare, nell'ordine. Per i dettagli di esercizio (aggiornamenti notturni, rollback,
limiti del proxy, comandi utili) vedi [`server/deploy/README.md`](../server/deploy/README.md);
per tutte le variabili [`server/README.md`](../server/README.md).

> Il deploy **non è mai stato provato** su una macchina vera: se qualcosa non torna, il
> primo posto dove guardare è `docker compose logs raen` (vedi "Se qualcosa non va").

## Cosa ti serve

| Cosa | Indicazione |
|---|---|
| **VPS** nell'UE | Ubuntu 24.04, 2 vCPU e 2–4 GB di RAM bastano per partire. Un provider europeo (Hetzner, OVH…) costa circa 4–8 €/mese. |
| **Dominio** | Anche un sottodominio, es. `api.tuodominio.it` (un dominio costa circa 10 €/anno). Deve già puntare alla VPS prima dell'avvio: serve a Caddy per ottenere il certificato. |
| **Contratto col provider** | Per il GDPR il provider è un responsabile del trattamento (art. 28): accetta il suo DPA (di solito una casella nel pannello). Poi annota il nome del provider in `lib/core/config/privacy_policy_info.dart` (campo hosting) e nel registro dei trattamenti (`docs/privacy/registro_trattamenti.md`). |
| Il Mac | Per copiare il server (`rsync`) e compilare l'app con l'indirizzo vero. |

### Cosa NON serve per questa prima prova

Gli account **Apple e Google** (App Store Connect, Play Console). In produzione il server esige
`PAYMENTS_MODE=real` e le chiavi (`MODERATION_KEY`, `ADMIN_TOKEN`,
`PAYMENTS_TRANSACTION_HASH_KEY`), ma **non** gli ID dei prodotti: lasciando vuote le righe
`APPLE_*` e `GOOGLE_*` gli acquisti rispondono 503 e il paywall resta "Non disponibile".
Le persone si vedono, richieste e chat funzionano. I pagamenti si accendono dopo, con gli
account degli store (`guida_per_sviluppatori.md` §3.6).

## Passi

### 1. Crea la VPS
Scegli Ubuntu 24.04 in una regione UE e aggiungi la tua chiave SSH (se non ne hai una:
`ssh-keygen -t ed25519`, poi incolla `~/.ssh/id_ed25519.pub` nel pannello). Annota l'**indirizzo IP**.

### 2. DNS
Dal pannello del dominio crea un record **A**: `api` → IP della VPS. Dopo qualche minuto:

```bash
dig +short api.tuodominio.it        # deve stampare l'IP della VPS
```

### 3. Prepara la macchina
Collegati come root (`ssh root@IP`) ed esegui:

```bash
apt update && apt -y upgrade
adduser raen && usermod -aG sudo raen        # un utente normale, non root
ufw allow OpenSSH && ufw allow 80 && ufw allow 443 && ufw --force enable
curl -fsSL https://get.docker.com | sh && usermod -aG docker raen
```

Esci, rientra come `ssh raen@IP` e controlla:

```bash
docker compose version
```

### 4. Copia il server
Dal Mac, dalla cartella del progetto (serve solo `server/`):

```bash
rsync -av --exclude build --exclude .dart_tool --exclude data \
  server/ raen@IP:~/raen/server/
```

### 5. Configura (sulla VPS, in `~/raen/server/deploy`)

```bash
mkdir -p secrets && chmod 700 secrets
cp .env.example .env && chmod 600 .env
openssl rand -base64 32     # → MODERATION_KEY
openssl rand -base64 32     # → PAYMENTS_TRANSACTION_HASH_KEY
openssl rand -hex 32        # → ADMIN_TOKEN
openssl rand -hex 32        # → METRICS_TOKEN
nano .env
```

Nel `.env` imposta:

| Variabile | Valore |
|---|---|
| `RAEN_DOMAIN` | `api.tuodominio.it` |
| `ACME_EMAIL` | la tua email (avvisi di scadenza del certificato) |
| `PAYMENTS_MODE` | `real` |
| `MODERATION_KEY`, `PAYMENTS_TRANSACTION_HASH_KEY`, `ADMIN_TOKEN`, `METRICS_TOKEN` | i quattro valori generati sopra |
| `APPLE_*`, `GOOGLE_*` | **vuote** per ora |
| `ATTESTATION_MODE` | `off` |

**Custodisci le chiavi** in un gestore di password, fuori dal repository (`.env` è escluso da git).
`MODERATION_KEY` e `PAYMENTS_TRANSACTION_HASH_KEY` non vanno perse né cambiate alla leggera:
cambiarle rende illeggibili i dati cifrati già scritti.

### 6. Avvia e verifica

```bash
docker compose build
docker compose up -d
docker compose ps                              # raen e caddy "running/healthy"
docker compose logs raen | head -30            # righe JSON: server.started, payments.mode…
curl -fsS https://api.tuodominio.it/           # {"service":"3mojo","status":"ok"}
```

### 7. Collega le app
Dal Mac, una build con l'indirizzo vero:

```bash
flutter build apk --debug --dart-define=API_BASE_URL=https://api.tuodominio.it
adb -s <ID> install -r build/app/outputs/flutter-apk/app-debug.apk
```

Poi, su ogni telefono:
1. Menu → opzioni sviluppatore → **spegni "dati finti"** e riavvia l'app.
2. Fai il profilo e **Start** con il selfie.
3. Prova **fuori dal Wi-Fi di casa** (dati mobili, o due posti diversi).
4. Restate fermi almeno **1 minuto** entrambi: la lista parte vuota.

Per le build di release (firma, Play Console) vedi `scripts/build_release.sh` e
`docs/privacy/checklist_prima_del_lancio.md` §2.1.

## Se qualcosa non va

| Sintomo | Cosa controllare |
|---|---|
| `raen` si riavvia in loop | `docker compose logs raen`: dice quale controllo di sicurezza è fallito (manca una chiave, `PAYMENTS_MODE` non è `real`, un token è troppo corto…). |
| `curl` dà errore di certificato | Il DNS non è ancora arrivato, oppure le porte 80/443 sono chiuse (firewall `ufw` o pannello del provider). `docker compose logs caddy` mostra il motivo. |
| I telefoni non si vedono | Non sono fermi da 1 minuto, il GPS al chiuso sbaglia di decine di metri (il raggio è circa 100 m), oppure uno dei due ha ancora "dati finti" acceso. |
| L'app dice che il server non è raggiungibile | La build non ha `API_BASE_URL=https://…`, oppure il certificato non è ancora valido. |
| Paywall "Non disponibile" | È voluto finché `APPLE_*`/`GOOGLE_*` sono vuote. |

## Dopo il primo avvio

- **Log in tempo reale:** `docker compose logs -f raen` (una riga JSON per evento, senza IP né token).
- **Aggiornare il server:** si fa di notte, perché un riavvio chiude tutte le sessioni in corso (lo
  stato è in RAM, per progetto). Procedura e rollback in `server/deploy/README.md` §4.
- **Cosa resta su disco:** solo gli hash degli sblocchi e i record di moderazione cifrati
  (30 giorni): tutto il resto sparisce a ogni riavvio.

## Tutto gratis nei primi mesi (e tornare a pagamento)

Il blocco delle foto lo decide **solo il server**, quindi si cambia senza toccare le app già
installate né aggiornare gli store.

**Accendere il "tutto gratis"** (sulla VPS, in `~/raen/server/deploy`):

```bash
nano .env                    # aggiungi la riga:  PAYWALL_MODE=free
docker compose up -d --no-deps raen
docker compose logs --since 1m raen | grep paywall     # deve dire "mode":"free"
```

**Tornare a pagamento**, quando vuoi: togli la riga `PAYWALL_MODE` (o scrivi `paid`) e ripeti
`docker compose up -d --no-deps raen`. Il log deve dire `"mode":"paid"`.

Cose da sapere:
- Un riavvio **chiude tutte le sessioni in corso** (chi è collegato vede "Server in riavvio" e rifà
  Start): meglio di notte, come ogni aggiornamento.
- Un valore scritto male (es. `fre`) **non** regala le foto: resta a pagamento e nel log compare
  un avviso `paywall.config`.
- Non dipende dai pagamenti: con `free` gli acquisti non servono, ma non vengono toccati. Chi
  aveva già uno sblocco continua ad averlo.
- Nelle schede degli store dichiara che l'app è gratuita al lancio e che gli acquisti arriveranno
  dopo: i revisori vogliono poterli verificare quando si accenderanno.
- Il server in locale (non in Docker) si avvia con `PAYWALL_MODE=free dart build/bin/server.dart`.

## Prima di aprire al pubblico (non servono per la prima prova)

- Account sviluppatore Apple e Google (come organizzazione), prodotti in-app e credenziali
  nel `.env` (`APPLE_*`, `GOOGLE_*`): `guida_per_sviluppatori.md` §3.6.
- Segnaposto da compilare nell'app: `privacy_policy_info.dart` (titolare, email, hosting,
  URL pubblico dell'informativa), `safety_contact.dart`, `store_config.dart` (ID prodotto),
  `attestation_config.dart`, `app_store_links.dart`.
- Chiave di firma Android (`android/key.properties`), scheda dello store e modulo Data safety
  (`docs/privacy/store_privacy.md`), test interno o chiuso su Play Console prima della produzione.
- Verifica del dispositivo (`ATTESTATION_MODE=log` e poi `enforce`): `guida_per_sviluppatori.md` §3.9.
- Traduzioni de/es/fr/ar riviste da un madrelingua.
- Un limite di connessioni per IP e un rate limit sul proxy (`server/deploy/README.md` §5).
