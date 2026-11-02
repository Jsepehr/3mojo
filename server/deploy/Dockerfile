# Immagine del server Raen.   Build dalla cartella server/:
#
#   docker build -f deploy/Dockerfile -t raen-server .
#
# Due stadi: si compila con dart_frog + `dart compile exe` (eseguibile AOT, un
# solo file) e si copia in un'immagine Debian minima.
#
# Perché non `FROM scratch`: il server chiama via HTTPS Apple (App Store
# Server API) e Google (Play Developer API, Play Integrity, OAuth); servono i
# certificati delle CA di sistema (/etc/ssl/certs), che `scratch` non ha. La
# base runtime installa `ca-certificates`.
#
# La libc del runtime deve essere quella di chi ha compilato: base build e
# base runtime sono entrambe Debian "bookworm" (verifica in fondo: se non
# coincidono, la build FALLISCE invece di partire e rompersi a runtime).

ARG DART_VERSION=stable
ARG RUNTIME_IMAGE=debian:bookworm-slim

# ---------- stadio 1: build ----------
FROM dart:${DART_VERSION} AS build
WORKDIR /app

# Dipendenze prima del codice (cache dei livelli). pubspec.lock è committato:
# le versioni sono quelle provate.
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

# La CLI di dart_frog serve SOLO per generare build/ (rotte -> bin/server.dart);
# resta nello stadio di build, non finisce nell'immagine finale.
RUN dart pub global activate dart_frog_cli
ENV PATH="$PATH:/root/.pub-cache/bin"

COPY . .
RUN dart pub get --offline
RUN dart_frog build

WORKDIR /app/build
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

# ---------- stadio 2: runtime ----------
FROM ${RUNTIME_IMAGE}

# CA di sistema (HTTPS verso Apple/Google), curl per l'healthcheck.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Utente non privilegiato; DATA_DIR e MODERATION_DIR sono volumi (compose).
RUN useradd --system --uid 10001 --home-dir /app --shell /usr/sbin/nologin raen \
 && mkdir -p /app /var/lib/raen/data /var/lib/raen/moderation \
 && chown -R raen:raen /app /var/lib/raen

COPY --from=build --chown=raen:raen /app/build/bin/server /app/server

# Se la libc non coincide con quella della build, ldd lo dice ORA.
RUN ! ldd /app/server 2>&1 | grep -qi "not found"

USER raen
WORKDIR /app

ENV PORT=8080 \
    DATA_DIR=/var/lib/raen/data \
    MODERATION_DIR=/var/lib/raen/moderation

EXPOSE 8080

# `GET /` è il controllo di salute (nessun dato sulle sessioni).
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/" >/dev/null || exit 1

# SIGTERM (docker stop) = spegnimento ordinato: vedi GracefulShutdown.
ENTRYPOINT ["/app/server"]
