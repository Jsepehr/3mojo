import 'package:dart_frog/dart_frog.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:threemojo_server/src/attestation/attestation_gate.dart';
import 'package:threemojo_server/src/client_ip.dart';
import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/session_lifecycle.dart';
import 'package:threemojo_server/src/socket_session.dart';

/// `GET /ws`, upgradato a WebSocket — un solo canale persistente per
/// sessione porta presenza/vicinanze, richieste d'incontro **e** i messaggi
/// di chat, spinti dal server appena cambia qualcosa invece che richiesti
/// dal client a intervalli. **Nessun parametro nell'URL**: il segreto della
/// sessione arriva col primo messaggio (vedi sotto), mai in query string.
///
/// Messaggi dal client, un JSON per frame di testo, distinti da `"type"`:
/// - `{"type": "hello", "secret": "<segreto>"}` — **obbligatorio e primo**,
///   entro 10 s, altrimenti il socket viene chiuso (codice 4001) senza aver
///   registrato nulla. Risposta: `welcome` (sotto), oppure
///   `{"type": "error", "code": "invalidSecret" | "rateLimited"}` e chiusura
///   (4002 / 4008) — oppure, con la verifica del dispositivo accesa e un
///   hello che aprirebbe una sessione **nuova**, prima un `challenge`
///   (sotto);
/// - `{"type": "attestation", "platform": "android", "token": ...}` /
///   `{"type": "attestation", "platform": "ios", "keyId": ...,
///   "attestationObject": ...}` (base64) / `{"type": "attestation"}` (sul
///   telefono l'attestazione non è riuscita) — **solo** come risposta a un
///   `challenge`, entro 25 s, e niente altro prima del `welcome`. Il token
///   Play Integrity (Standard API) va chiesto con `requestHash =
///   hex(SHA-256(utf8(nonce)))`; la chiave App Attest va **generata nuova**
///   e attestata con `clientDataHash = SHA-256(utf8(nonce))`. Esito:
///   `welcome`, oppure `{"type": "error", "code": "attestationRequired"}` e
///   chiusura 4011 (solo con `ATTESTATION_MODE=enforce`; con `log` si passa
///   sempre), oppure `rateLimited` e 4008 (troppe attestazioni dallo stesso
///   IP). Un'attestazione vale una volta sola, solo su questo socket;
///   le riconnessioni di una sessione viva non la richiedono. Nulla
///   dell'attestazione viene conservato (vedi `AttestationGate`);
/// - `{"type": "presence", "lat": ..., "lng": ..., "gender": ...,
///   "lookingFor": [...], "intent": ..., "languages": [...],
///   "showGender": bool, "selfieBase64": ..., "unlockToken": ...}` — dopo
///   ogni `welcome` e poi a ogni aggiornamento di posizione. Profilo e
///   selfie (JPEG, ≤ ~230 KB) contano solo alla nascita della sessione:
///   dopo si possono omettere. `unlockToken` solo se si è pagato. Il server
///   usa **al più una posizione ogni 10 s** per sessione
///   (`SessionStore.minPositionInterval`): quelle in più sono ignorate in
///   silenzio (token e selfie mancante sono comunque presi), senza rifiuto
///   né chiusura;
/// - `{"type": "sendEncounterRequest", "toPersonId": ..., "proposal": ...}`
///   — `proposal` è cosa si propone, un codice della lista chiusa
///   `EncounterProposal` (`sayHi`, `chat`, `friendship`, `getToKnow`,
///   `drink`): mancante (client vecchi) o sconosciuto vale `getToKnow`. Mai
///   testo libero: la frase la traduce il client di chi riceve;
/// - `{"type": "respondToEncounterRequest", "requestId": ..., "accepted": bool}`;
/// - `{"type": "endMatch", "requestId": ...}`;
/// - `{"type": "chatMessage", "toPersonId": ..., "text": ...,
///   "clientMessageId": ...}` (l'ultimo facoltativo) — inoltrato solo con un
///   match attivo, mai conservato (il server fa solo da postino); un testo
///   oltre 1000 unità UTF-16 torna `rejected` `invalidText` (il socket resta
///   aperto, solo un frame oltre 16 KB lo chiude con 4009);
/// - `{"type": "block", "personId": ...}` — blocca la persona (uno
///   pseudonimo ricevuto): da subito, e per tutta la vita della propria
///   sessione (anche attraverso grazia e riconnessioni), i due non si
///   vedono più in "Vicinanze", le richieste tra loro sono cancellate (il
///   match, se c'è, chiuso), la chat non passa. Nessuna conferma; rifiuto
///   `rejected` `unknownPerson` se lo pseudonimo non si risolve (vedi
///   `BlockStore`). Non sopravvive a End/nuovo Start (niente id permanenti);
/// - `{"type": "report", "personId": ..., "reason": ...}` — segnala (e
///   **blocca**) la persona. `reason` dalla lista chiusa `ReportReason`
///   (`fakePhoto`, `inappropriatePhoto`, `harassment`, `underage`, `spam`,
///   `other`), niente testo libero. Rifiuti: `invalidReason` (motivo
///   mancante o fuori lista: nessun effetto, nemmeno il blocco),
///   `unknownPerson`, `tooManyReports` (oltre 5 segnalazioni nella sessione:
///   il blocco vale comunque, la segnalazione no). Da 3 sessioni diverse e
///   2 IP diversi la sessione segnalata viene chiusa (`sessionClosed`,
///   sotto) e il suo IP non può fare nuovi Start per 30 minuti; ogni
///   segnalazione aggiorna il record di moderazione cifrato (vedi
///   `ModerationStore`, `ModerationRecordStore`);
/// - `{"type": "ping"}` — ogni 20 s, per dire "sono vivo" (risposta:
///   `pong`);
/// - `{"type": "end"}` — End esplicito: la sessione finisce subito.
///
/// Messaggi dal server:
/// - `{"type": "challenge", "nonce": ..., "expiresInSeconds": 20}` — solo
///   con `ATTESTATION_MODE` `log` o `enforce`, dopo un `hello` che
///   aprirebbe una sessione nuova: il nonce (32 byte casuali, base64url)
///   vale una volta, per questo socket, per `expiresInSeconds` secondi. Con
///   `off` (default) non arriva mai e dopo `hello` c'è subito `welcome`;
/// - `{"type": "welcome", "resumed": bool, "graceSeconds": 45}` — dopo un
///   hello valido; `resumed: true` = stessa sessione di prima (stessa
///   permanenza, richieste e match), `false` = sessione nuova;
/// - `{"type": "nearby", "people": [{"personId", "meetingChance", "locked",
///   "selfieBase64"?, "intent"?, "languages"?, "gender"?}]}` — ordinata per
///   fasce di distanza di 25 m (dentro una fascia, un ordine fisso per chi
///   guarda), **senza distanze**; `locked` = dietro il paywall (niente
///   selfie). **Vuota per il primo minuto** della sessione e dopo ogni
///   spostamento confermato: anche chi guarda dev'essere fermo da un minuto
///   (le distanze vanno da ancora ad ancora, vedi `SessionStore`). Al più
///   una lista diversa ogni 5 s per sessione
///   (`ConnectionHub.nearbyPushMinInterval`);
/// - `{"type": "encounters", "incoming": [...], "outgoing": [...]}`, ogni
///   richiesta `{"id", "otherPersonId", "status", "proposal",
///   "otherSelfieBase64"?, "otherIntent"?, "otherLanguages"?,
///   "otherGender"?}` (`proposal` sempre, per entrambi i lati e in ogni
///   stato: cosa ha proposto chi ha chiesto; selfie e profilo solo per
///   `pending`/`accepted`; il selfie solo la prima volta per richiesta su
///   ogni socket, poi il client riusa quello già ricevuto);
/// - `{"type": "pong"}` — risposta a ogni `ping`;
/// - `{"type": "chatMessage", "fromPersonId": ..., "text": ..., "sentAt": ...}`;
/// - `{"type": "rejected", "action": ..., "reason": ..., ...}` — un'azione
///   rifiutata dalle regole del server (vedi `RealtimeMessageHandler`); per
///   `block`/`report` c'è anche `personId`;
/// - `{"type": "sessionClosed", "reason": "reports"}` — la sessione è stata
///   chiusa dal server dopo abbastanza segnalazioni: subito dopo il socket
///   si chiude (4010) e la sessione non esiste più (un nuovo `hello` con lo
///   stesso segreto è un nuovo Start, e dallo stesso IP torna `rateLimited`
///   per il cooldown).
///
/// **Cosa vede chi viene bloccato**: esattamente ciò che vedrebbe se l'altro
/// avesse premuto End — la richiesta tra loro `cancelled` (o il match
/// `ended`) nel suo snapshot normale e poi più nulla, l'altro sparisce dalle
/// "Vicinanze" (entro 5 s), e ogni azione col vecchio pseudonimo fallisce
/// come verso chi è uscito (`notNearby`, `notDelivered`, `unknownPerson`).
/// Nessun messaggio dice "sei stato bloccato".
///
/// **Id**: `personId`/`otherPersonId`/`fromPersonId` sono pseudonimi per
/// osservatore (`Pseudonyms`): la stessa persona ha un id diverso per ognuno
/// che la vede, e il client rimanda indietro quello che ha ricevuto.
///
/// **Chiusura**: con `end` (o con `sessionClosed`) la sessione finisce
/// subito; ogni altra chiusura
/// (rete persa, app uccisa) la nasconde e avvia un periodo di grazia di 45 s
/// in cui riconnettersi con lo stesso segreto la riprende intatta (vedi
/// `SessionLifecycle`). Il server manda un ping WebSocket ogni 20 s
/// ([pingInterval]): un socket morto senza chiusura viene scoperto e chiuso.
Future<Response> onRequest(RequestContext context) async {
  final clientIp = resolveClientIp(
    remoteAddress: context.request.connectionInfo.remoteAddress.address,
    forwardedFor: context.request.headers['x-forwarded-for'],
    trustedProxies: _trustedProxies,
  );

  SessionLifecycle.instance.startAutoPurge();
  ConnectionHub.instance.startHotspotDetection();

  final handler = fromShelfHandler(
    webSocketHandler((webSocket, protocol) {
      SocketSession(
        incoming: webSocket.stream,
        outgoing: webSocket.sink,
        clientIp: clientIp,
        attestation: AttestationGate.instance,
      ).start();
    }, pingInterval: pingInterval),
  );

  return handler(context);
}

/// Ping WebSocket del server: senza, un socket mezzo aperto (telefono che
/// perde la rete senza chiudere) resterebbe "connesso" per minuti.
const pingInterval = Duration(seconds: 20);

final Set<String> _trustedProxies = trustedProxiesFromEnvironment();
