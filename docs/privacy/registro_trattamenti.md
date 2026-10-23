# Raen: registro delle attività di trattamento (art. 30 GDPR)

> **Bozza tecnica, non consulenza legale.** I campi tra parentesi quadre li compila il titolare. Le descrizioni tecniche corrispondono al codice al commit `4f7cae1` più la rimozione di ML Kit, e alla [DPIA](dpia.md) versione 0.2, che riporta anche i file di riferimento.

## Dati del titolare

| Campo | Valore |
|---|---|
| Titolare | **[Ragione sociale, sede legale, P.IVA]** |
| Rappresentante legale | **[Nome]** |
| Contatto privacy | **[email dedicata, es. privacy@…]** |
| Contatto di sicurezza (in app) | **[oggi segnaposto `safety@raen.example` in `lib/core/config/safety_contact.dart`: da sostituire]** |
| DPO | **[Nome e contatti, oppure "non nominato" con la motivazione]** |
| Rappresentante UE (art. 27) | **[Solo se il titolare non è stabilito nell'UE]** |
| Data di compilazione / ultimo aggiornamento | 23/10/2026 (bozza) |

## Responsabili e terze parti

| Soggetto | Servizio | Ruolo proposto (da validare) | Paese / trasferimento | Contratto |
|---|---|---|---|---|
| **[Fornitore di hosting]** | Server Dart Frog, disco dei record di moderazione, reverse proxy | Responsabile (art. 28) | **[UE raccomandato]** | **[DPA da firmare]** |
| **[Fornitore email]** | Casella del contatto di sicurezza e della privacy | Responsabile (art. 28) | **[ ]** | **[DPA]** |
| Apple Inc. / Apple Distribution International | App Store, acquisti in-app (StoreKit), App Attest (quando acceso) | Titolare autonomo per distribuzione e pagamenti; da qualificare per App Attest | USA/Irlanda, DPF o SCC dei termini Apple (da verificare) | Apple Developer Program License Agreement |
| Google LLC / Google Ireland | Google Play, Play Billing (compresa l'eventuale diagnostica della Play Billing Library, da verificare), Play Integrity (quando acceso) | Titolare autonomo per Play e Billing; da qualificare per Play Integrity e per la diagnostica della Billing Library, se confermata (possibile contitolarità) | USA/Irlanda, DPF o SCC dei termini Google (da verificare) | Developer Distribution Agreement, Android SDK License (Billing), termini Play Integrity |

## Attività di trattamento

### T1. Presenza e "Vicinanze"

| Campo | Contenuto |
|---|---|
| Finalità | Mostrare all'utente le persone fisicamente vicine e compatibili, e mostrare lui a loro |
| Base giuridica | Art. 6(1)(b). Per genere e "chi cerca": art. 9(2)(a), consenso esplicito in app (salvo il percorso neutro) |
| Interessati | Utenti dell'app (dichiarati maggiorenni) |
| Categorie di dati | Posizione precisa; selfie della sessione; genere, "chi cerca" (categoria particolare), intento, lingue, scelta di mostrare il genere; stadio di permanenza; segreto e id interno di sessione; pseudonimi |
| Destinatari | Altri utenti compatibili entro 100 m (o nello stesso posto affollato): pseudonimo, selfie (se non dietro il paywall), intento, lingue, genere se mostrato, stadio. **Mai** coordinate, distanze né "chi cerca". Hosting |
| Trasferimenti extra UE | Nessuno, se l'hosting è nell'UE |
| Conservazione | RAM del server per la durata della sessione (fino a End; 45 s di grazia dopo una caduta; chiusura dopo 90 s senza messaggi). Il profilo resta solo sul telefono, cifrato, fino alla cancellazione |
| Misure di sicurezza | TLS; ancore, osservatore fermo, fasce di 25 m, nessuna distanza al client; pseudonimi per osservatore; matching reciproco; profilo fissato alla nascita della sessione; limiti per IP e per connessione; cifratura del profilo sul telefono; EXIF rimosso (DPIA §5, M1-M14, M20-M21, M25) |

### T2. Richieste d'incontro e chat

| Campo | Contenuto |
|---|---|
| Finalità | Proporre, accettare o rifiutare un incontro; comunicare con il match |
| Base giuridica | Art. 6(1)(b) |
| Interessati | Utenti dell'app |
| Categorie di dati | Proposta (lista chiusa), stato della richiesta, testo dei messaggi, ora del server. Contenuto libero della chat: può includere qualunque dato, a scelta di chi scrive |
| Destinatari | La controparte. Il server fa solo da inoltro |
| Conservazione | Richieste: RAM del server per la sessione. Messaggi: **nessuna** sul server; RAM del telefono fino a fine match o End |
| Misure | Un incontro alla volta; una richiesta per coppia; chat solo con un match attivo; nessun salvataggio su disco (M15, M13) |

### T3. Sicurezza: blocchi, segnalazioni, chiusura automatica

| Campo | Contenuto |
|---|---|
| Finalità | Tutelare gli utenti da molestie, foto false o inappropriate, minori, spam; escludere temporaneamente chi viene segnalato da più persone |
| Base giuridica | Art. 6(1)(f), interesse legittimo alla sicurezza degli utenti e del servizio (bilanciamento da documentare); eventuali obblighi DSA, art. 6(1)(c) |
| Interessati | Chi segnala, chi blocca, chi è segnalato o bloccato |
| Categorie di dati | Id interni delle sessioni, motivo della segnalazione (lista chiusa), IP di chi segnala e IP usati dalla sessione segnalata |
| Destinatari | Nessuno (trattamento automatico sul server) |
| Conservazione | RAM: per la vita delle sessioni coinvolte. Cooldown sull'IP: 30 minuti (configurabile) |
| Decisioni automatiche | Chiusura della sessione con segnalazioni da ≥ 3 sessioni e ≥ 2 IP, più 30 minuti di blocco dei nuovi Start da quegli IP. Ricorso: contatto di sicurezza |
| Misure | Soglie su più sessioni e IP; al più 5 segnalazioni per sessione; doppioni non conteggiati (M16, M26) |

### T4. Record di moderazione

| Campo | Contenuto |
|---|---|
| Finalità | Revisione umana delle segnalazioni, ricorsi, prevenzione degli abusi |
| Base giuridica | Art. 6(1)(f); eventuale art. 6(1)(c) (DSA) |
| Interessati | Persone segnalate |
| Categorie di dati | Selfie della persona segnalata (senza metadati), motivi con conteggio, numero di segnalazioni, se è scattata la chiusura, creazione e aggiornamento arrotondati al minuto, id casuale. **Niente** posizione, chat, IP, id, pseudonimi né profilo |
| Destinatari | Personale incaricato della moderazione **[nominativi o funzione, istruzioni scritte art. 29]**. Hosting |
| Conservazione | 30 giorni dalla creazione, poi cancellazione automatica; prima, cancellazione manuale a revisione conclusa |
| Misure | AES-256-GCM (`MODERATION_KEY` fuori dal repository e dai backup dei record); endpoint admin solo su TLS, token ≥ 32 caratteri, confronto a tempo costante, 120 richieste per IP ogni 10 minuti (M24) |

### T5. Prevenzione degli abusi per IP

| Campo | Contenuto |
|---|---|
| Finalità | Limitare i nuovi Start, gli acquisti, le attestazioni e le chiamate admin per IP |
| Base giuridica | Art. 6(1)(f) |
| Categorie di dati | Indirizzo IP, orari |
| Conservazione | RAM: finestre di 1-10 minuti; ≤ 5 IP per sessione per la durata della sessione; cooldown 30 minuti |
| Note | I **log del reverse proxy e del provider** contengono IP: conservazione **[da definire, raccomandati ≤ 7 giorni]** |

### T6. Sblocco a pagamento

| Campo | Contenuto |
|---|---|
| Finalità | Vendere e verificare lo sblocco di 2 ore; emetterlo una volta sola per transazione; revocarlo in caso di rimborso |
| Base giuridica | Art. 6(1)(b) |
| Categorie di dati | Piattaforma, prodotto, transazione firmata (iOS) o `purchaseToken` (Android); token di sblocco casuale |
| Destinatari | Apple, Google (verifica, consumo, notifiche di rimborso) |
| Conservazione | Token: 2 ore (telefono cifrato, server in RAM). Registro anti-doppio riscatto: **HMAC** della transazione più la data, 8 giorni in RAM |
| Stato | Oggi **simulato** (`PAYMENTS_MODE=fake`; in release, senza `REAL_PAYMENTS`, il pagamento non è disponibile) |

### T7. Verifica del dispositivo

| Campo | Contenuto |
|---|---|
| Finalità | Accettare sessioni nuove solo dall'app originale su un dispositivo reale (contro script e sessioni parallele) |
| Base giuridica | Art. 6(1)(f). Da valutare l'art. 5(3) ePrivacy / art. 122 Codice |
| Categorie di dati | Token Play Integrity; oggetto di attestazione App Attest con una chiave nuova a ogni sessione; esito |
| Destinatari | Google, Apple |
| Conservazione | Nulla dopo la verifica; contatori aggregati e orari per IP per 1 minuto |
| Stato | Predisposta e **spenta** (`ATTESTATION_MODE=off`) |

### T8. Rilevamento del volto sul telefono

| Campo | Contenuto |
|---|---|
| Finalità | Verificare che il selfie contenga un volto prima dello Start |
| Base giuridica | Art. 6(1)(b). Nessun trattamento biometrico: non c'è identificazione né confronto, e nulla lascia il telefono |
| Note | Android: `android.media.FaceDetector`, del sistema operativo, senza rete. iOS: Apple Vision, senza rete. Nessuna libreria di terzi e nessuna telemetria (fino alla DPIA 0.1 c'era Google ML Kit, che inviava a Google diagnostica con un id per installazione: tolto). Il titolare non riceve dati |
| Conservazione | File temporaneo cancellato sempre a fine controllo |

### T9. Contatti al supporto, sicurezza e privacy

| Campo | Contenuto |
|---|---|
| Finalità | Rispondere a segnalazioni, ricorsi e richieste di esercizio dei diritti |
| Base giuridica | Art. 6(1)(c) (artt. 12-22) e 6(1)(f) |
| Categorie di dati | Indirizzo email e contenuto del messaggio; eventuali elementi forniti per riconoscere un record di moderazione |
| Conservazione | **[da definire, es. 12 mesi dalla chiusura della pratica]** |
| Destinatari | Fornitore email (responsabile) |

## Dati che restano solo sul telefono (fuori dal controllo del titolare)

Profilo cifrato, impostazioni (lingua, tema), segno d'installazione, token di sblocco finché vale. Il titolare non vi accede: sono elencati per trasparenza. Il profilo va comunque al server durante la sessione (T1).
