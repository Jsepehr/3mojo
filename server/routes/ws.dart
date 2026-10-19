import 'package:dart_frog/dart_frog.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
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
///   (4002 / 4008);
/// - `{"type": "presence", "lat": ..., "lng": ..., "gender": ...,
///   "lookingFor": [...], "intent": ..., "languages": [...],
///   "showGender": bool, "selfieBase64": ..., "unlockToken": ...}` — dopo
///   ogni `welcome` e poi a ogni aggiornamento di posizione. Profilo e
///   selfie (JPEG, ≤ ~230 KB) contano solo alla nascita della sessione:
///   dopo si possono omettere. `unlockToken` solo se si è pagato;
/// - `{"type": "sendEncounterRequest", "toPersonId": ...}`;
/// - `{"type": "respondToEncounterRequest", "requestId": ..., "accepted": bool}`;
/// - `{"type": "endMatch", "requestId": ...}`;
/// - `{"type": "chatMessage", "toPersonId": ..., "text": ...,
///   "clientMessageId": ...}` (l'ultimo facoltativo) — inoltrato solo con un
///   match attivo, mai conservato (il server fa solo da postino); un testo
///   oltre 1000 unità UTF-16 torna `rejected` `invalidText` (il socket resta
///   aperto, solo un frame oltre 16 KB lo chiude con 4009);
/// - `{"type": "ping"}` — ogni 20 s, per dire "sono vivo" (risposta:
///   `pong`);
/// - `{"type": "end"}` — End esplicito: la sessione finisce subito.
///
/// Messaggi dal server:
/// - `{"type": "welcome", "resumed": bool, "graceSeconds": 45}` — dopo un
///   hello valido; `resumed: true` = stessa sessione di prima (stessa
///   permanenza, richieste e match), `false` = sessione nuova;
/// - `{"type": "nearby", "people": [{"personId", "meetingChance", "locked",
///   "selfieBase64"?, "intent"?, "languages"?, "gender"?}]}` — già ordinata
///   dalla persona più vicina, **senza distanze**; `locked` = dietro il
///   paywall (niente selfie);
/// - `{"type": "encounters", "incoming": [...], "outgoing": [...]}`, ogni
///   richiesta `{"id", "otherPersonId", "status", "otherSelfieBase64"?,
///   "otherIntent"?, "otherLanguages"?, "otherGender"?}` (selfie e profilo
///   solo per `pending`/`accepted`; il selfie solo la prima volta per
///   richiesta su ogni socket, poi il client riusa quello già ricevuto);
/// - `{"type": "pong"}` — risposta a ogni `ping`;
/// - `{"type": "chatMessage", "fromPersonId": ..., "text": ..., "sentAt": ...}`;
/// - `{"type": "rejected", "action": ..., "reason": ..., ...}` — un'azione
///   rifiutata dalle regole del server (vedi `RealtimeMessageHandler`).
///
/// **Id**: `personId`/`otherPersonId`/`fromPersonId` sono pseudonimi per
/// osservatore (`Pseudonyms`): la stessa persona ha un id diverso per ognuno
/// che la vede, e il client rimanda indietro quello che ha ricevuto.
///
/// **Chiusura**: con `end` la sessione finisce subito; ogni altra chiusura
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
      ).start();
    }, pingInterval: pingInterval),
  );

  return handler(context);
}

/// Ping WebSocket del server: senza, un socket mezzo aperto (telefono che
/// perde la rete senza chiudere) resterebbe "connesso" per minuti.
const pingInterval = Duration(seconds: 20);

final Set<String> _trustedProxies = trustedProxiesFromEnvironment();
