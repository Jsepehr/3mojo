# Attestazioni App Attest vere, per i test

File copiati **senza modifiche** dal pacchetto MIT
[jewei/app-attest-php](https://github.com/jewei/app-attest-php) (`spec/`),
scaricati il 2026-10-23; impronte SHA-256 dei file uguali a quelle del suo
`spec/provenance.json`.

- `apple-sample-attestation.json` — l'attestazione d'esempio pubblicata da
  Apple nell'[Attestation Object Validation Guide](https://developer.apple.com/documentation/devicecheck/attestation-object-validation-guide)
  (App ID `1234567890.com.example.myapp`, ambiente production). Nell'esempio
  l'app passa i byte del testo `example_server_challenge` **direttamente**
  come `clientDataHash` (non il suo SHA-256): per questo il test usa
  `AppAttestVerifier.verifyAttestation` con quei byte. Certificato valido dal
  2026-04-20 al 2026-04-23: il test fissa l'orologio.
  SHA-256 dell'attestation object decodificato:
  `e4ca508153f6619a29d0887eb0ffe19540b9f15c5a6aeccdac26c49affd5f61a`.
- `termakan-ios27-attestation.json` — un'attestazione vera da un iPhone con
  iOS 27.0.1 (App ID `4L4SS26L9J.com.jewei.termakan`, ambiente production),
  con lo stesso schema di Raen: `clientDataHash = SHA-256(utf8(challenge))`.
  Chiave mai registrata su nessun server. Certificato valido dal 2026-10-11
  al 2026-10-14. SHA-256 del file:
  `c65797c5b0243e68c744aa90edb752bcb320d757887ce36e963c3a19c787d1ad`.
  Licenza MIT, vedi `LICENSE-app-attest-php`.

Nessuno dei due contiene dati di una persona: sono chiavi di prova di
sviluppatori.
