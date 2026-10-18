# threemojo_server

[![style: dart frog lint][dart_frog_lint_badge]][dart_frog_lint_link]
[![License: MIT][license_badge]][license_link]
[![Powered by Dart Frog](https://img.shields.io/endpoint?url=https://tinyurl.com/dartfrog-badge)](https://dart-frog.dev)

An example application built with dart_frog

[dart_frog_lint_badge]: https://img.shields.io/badge/style-dart_frog_lint-1DF9D2.svg
[dart_frog_lint_link]: https://pub.dev/packages/dart_frog_lint
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
## Variabili d'ambiente

| Variabile | Effetto |
|---|---|
| `TLS_CERT_PATH` + `TLS_KEY_PATH` | Percorsi di catena di certificati e chiave privata (PEM). Se presenti entrambe il server parla **solo** `https://`/`wss://` (vedi `main.dart`). Con una sola delle due si rifiuta di partire. |
| `DEBUG_ENDPOINTS_TOKEN` | Accende `GET /debug/sessions`, che risponde solo con l'header `X-Debug-Token` uguale a questo valore. Senza, l'endpoint risponde 404. Da non impostare in produzione. |

Senza `TLS_*` il server resta in chiaro: va bene in sviluppo locale, in
produzione **solo** dietro un reverse proxy che termina TLS. L'app in release
accetta comunque solo `API_BASE_URL=https://…`.

Il `sessionId` che il client passa a `/ws` è una credenziale segreta: il
server lo traduce subito in un id pubblico casuale (`SessionCredentials`) ed è
solo quello a comparire nei messaggi verso gli altri utenti.
