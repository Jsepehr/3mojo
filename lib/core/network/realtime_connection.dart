import 'dart:async';
import 'dart:convert';

import '/core/errors/exceptions.dart';
import 'api_config.dart';
import 'realtime_socket.dart';
import 'realtime_socket_web.dart'
    if (dart.library.io) 'realtime_socket_io.dart'
    as platform;
import 'reconnect_backoff.dart';

/// In che stato è la connessione condivisa.
enum RealtimeStatus {
  /// Nessuna sessione (mai connessa, o dopo [RealtimeConnection.disconnect]).
  offline,

  /// Primo tentativo in corso per questa sessione.
  connecting,

  /// Il server ha risposto `welcome`: [RealtimeConnection.send] funziona.
  online,

  /// La connessione è caduta e si sta riprovando da soli (backoff).
  reconnecting,
}

/// Un'unica connessione WebSocket persistente per sessione (`GET /ws`),
/// condivisa tra le feature che ne hanno bisogno — `nearby`
/// (presenza/vicinanze), `encounters` (richieste d'incontro) e `chat`: un
/// solo socket fisico per sessione, ognuno filtra i messaggi del proprio
/// `"type"` dallo stesso stream. Sta in `core/` perché nessuna feature
/// dipenda da un'altra solo per condividere il canale.
///
/// **Protocollo** (vedi `server/routes/ws.dart`): il segreto di sessione
/// non va nell'URL ma nel primo messaggio (`hello`); il server risponde
/// `welcome` e solo da lì in poi [send] manda davvero qualcosa. Ogni 20 s
/// parte un `ping` applicativo (su mobile/desktop c'è anche il ping
/// WebSocket nativo, vedi `realtime_socket_io.dart`).
///
/// **Riconnessione centralizzata qui**: se il socket cade (rete persa,
/// server riavviato), lo stream ritornato da [connect] **non** si chiude —
/// emette un errore (`ServerException`, che i repository traducono in
/// `ConnectionFailure`) e intanto si riprova da soli con backoff
/// esponenziale e jitter (0,5 → 30 s, [ReconnectBackoff]). Il server tiene
/// la sessione intatta per 45 s di grazia: se si rientra in tempo, il
/// `welcome` dice `resumed: true` e tutto (permanenza, richieste, match)
/// riprende com'era; altrimenti `resumed: false` e lato server è una
/// sessione nuova (vedi [onReady]). Lo stream si chiude solo con
/// [disconnect] (End) o passando a un'altra sessione.
///
/// **Socket morti senza chiusura** (l'app torna in primo piano dopo che il
/// telefono ha cambiato rete o è stato sospeso a lungo): [checkAlive] manda
/// un `ping` e, se dal server non arriva nulla entro [probeTimeout] (il
/// server risponde `pong`), abbandona il socket e si riconnette subito —
/// invece di aspettare che il sistema operativo se ne accorga da sé.
class RealtimeConnection {
  RealtimeConnection({
    RealtimeSocketFactory? socketFactory,
    ReconnectBackoff? backoff,
    this.pingInterval = const Duration(seconds: 20),
    this.probeTimeout = const Duration(seconds: 5),
    this.farewellTimeout = const Duration(seconds: 5),
    Uri Function()? endpoint,
  }) : _socketFactory = socketFactory ?? platform.connectRealtimeSocket,
       _backoff = backoff ?? ReconnectBackoff(),
       _endpoint = endpoint ?? (() => Uri.parse('${ApiConfig.wsBaseUrl}/ws'));

  static final RealtimeConnection instance = RealtimeConnection();

  /// Codice con cui il server chiude un socket che ha superato il limite di
  /// nuovi Start per IP: inutile riprovare subito.
  static const closeCodeRateLimited = 4008;

  final RealtimeSocketFactory _socketFactory;
  final ReconnectBackoff _backoff;
  final Uri Function() _endpoint;
  final Duration pingInterval;

  /// Quanto aspettare una risposta del server dopo [checkAlive] prima di
  /// considerare morto il socket.
  final Duration probeTimeout;

  /// Quanto può durare al massimo il socket "d'addio" che porta `end` dopo
  /// un [disconnect] arrivato mentre si era in riconnessione.
  final Duration farewellTimeout;

  final StreamController<RealtimeStatus> _statusChanges =
      StreamController.broadcast();
  final StreamController<bool> _readyEvents = StreamController.broadcast();

  String? _sessionId;
  StreamController<Map<String, dynamic>>? _messages;
  RealtimeSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _probeTimer;

  /// Attivo dalla caduta di un socket che era pronto fino alla fine della
  /// grazia annunciata dal server (`graceSeconds` del `welcome`): in questa
  /// finestra il server ha ancora la sessione, e un End va recapitato.
  Timer? _serverGraceTimer;
  Duration _serverGrace = const Duration(seconds: 45);
  bool _ready = false;
  RealtimeStatus _status = RealtimeStatus.offline;

  RealtimeStatus get status => _status;

  /// Ogni cambio di [status].
  Stream<RealtimeStatus> get statusChanges => _statusChanges.stream;

  /// `true` dopo il `welcome` del socket attuale: [send] può mandare.
  bool get isReady => _ready;

  /// Emette a ogni `welcome` (primo collegamento e ogni riconnessione) il
  /// suo `resumed`: `true` = il server aveva ancora la sessione (stessa
  /// permanenza, richieste e match), `false` = sessione nuova lato server
  /// (prima volta, o grazia scaduta). È il momento di rimandare lo stato
  /// iniziale (la presenza col selfie, vedi `NearbyRemoteDataSourceImpl`).
  Stream<bool> get onReady => _readyEvents.stream;

  /// Apre (o riusa) la connessione per [sessionId] e ritorna lo stream
  /// broadcast dei messaggi JSON in arrivo, condiviso da tutti. Chiamabile
  /// da più feature: con la stessa sessione ritorna lo stesso stream (e, se
  /// si stava aspettando il prossimo tentativo, riprova subito — es. il
  /// bottone "Riprova"); con una sessione **diversa** chiude prima quella
  /// vecchia (mandando `end`).
  Stream<Map<String, dynamic>> connect(String sessionId) {
    final current = _messages;
    if (_sessionId == sessionId && current != null && !current.isClosed) {
      if (_socket == null) {
        _reconnectTimer?.cancel();
        _openSocket();
      }
      return current.stream;
    }

    if (_sessionId != null) unawaited(_closeCurrent());

    final messages = StreamController<Map<String, dynamic>>.broadcast();
    _sessionId = sessionId;
    _messages = messages;
    _backoff.reset();
    _setStatus(RealtimeStatus.connecting);
    _openSocket();
    return messages.stream;
  }

  void _openSocket() {
    final sessionId = _sessionId;
    final messages = _messages;
    if (sessionId == null || messages == null) return;

    final RealtimeSocket socket;
    try {
      socket = _socketFactory(_endpoint());
    } catch (error) {
      _onSocketGone(null, messages, ServerException(error.toString()));
      return;
    }
    _socket = socket;
    _ready = false;

    _socketSubscription = socket.stream.listen(
      (raw) => _onFrame(socket, messages, raw),
      // Server irraggiungibile, rete caduta: l'errore vero lo racconta
      // `onDone` (con la riconnessione), qui basta non lasciarlo non gestito.
      onError: (Object _) {},
      onDone: () => _onSocketGone(
        socket,
        messages,
        const ServerException('Connessione al server persa'),
      ),
      cancelOnError: false,
    );

    socket.ready.then((_) {
      if (!identical(_socket, socket)) return;
      try {
        // Il segreto viaggia solo qui, mai nell'URL.
        socket.add(jsonEncode({'type': 'hello', 'secret': sessionId}));
      } catch (_) {
        // Il socket si è chiuso nel frattempo: ci pensa `onDone`.
      }
    }, onError: (Object _) {});
  }

  void _onFrame(
    RealtimeSocket socket,
    StreamController<Map<String, dynamic>> messages,
    dynamic raw,
  ) {
    if (!identical(_socket, socket)) return;
    // Qualsiasi frame dal server (il `pong` di [checkAlive] o altro) dice
    // che il socket è vivo.
    _probeTimer?.cancel();
    _probeTimer = null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw as String);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    if (decoded['type'] == 'welcome') {
      final graceSeconds = decoded['graceSeconds'];
      if (graceSeconds is int && graceSeconds > 0) {
        _serverGrace = Duration(seconds: graceSeconds);
      }
      _serverGraceTimer?.cancel();
      _serverGraceTimer = null;
      _ready = true;
      _backoff.reset();
      _setStatus(RealtimeStatus.online);
      _startPing();
      _readyEvents.add(decoded['resumed'] == true);
    }
    if (!messages.isClosed) messages.add(decoded);
  }

  void _onSocketGone(
    RealtimeSocket? socket,
    StreamController<Map<String, dynamic>> messages,
    ServerException error,
  ) {
    if (socket != null && !identical(_socket, socket)) return;
    final wasReady = _ready;
    _socket = null;
    _socketSubscription = null;
    _ready = false;
    _stopPing();
    _probeTimer?.cancel();
    _probeTimer = null;

    // Chiuso da `disconnect()` o sostituito da un'altra sessione: niente da
    // riprovare.
    if (_sessionId == null || !identical(_messages, messages)) return;

    if (wasReady) {
      _serverGraceTimer?.cancel();
      _serverGraceTimer = Timer(_serverGrace, () => _serverGraceTimer = null);
    }
    if (!messages.isClosed) messages.addError(error);
    if (socket?.closeCode == closeCodeRateLimited) _backoff.jumpToMax();
    _setStatus(RealtimeStatus.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_backoff.next(), _openSocket);
  }

  /// Controlla che la connessione sia davvero viva — da chiamare quando
  /// l'app torna in primo piano (vedi `CheckConnectionUseCase`):
  /// - in attesa del prossimo tentativo di riconnessione: riprova subito;
  /// - socket aperto: manda un `ping` (se il server ha già detto `welcome`)
  ///   e, se entro [probeTimeout] non arriva nessun frame, lo abbandona
  ///   (chiudendolo senza `end`, così sul server parte la grazia) e si
  ///   riconnette subito.
  ///
  /// Senza sessione non fa nulla.
  void checkAlive() {
    final messages = _messages;
    if (_sessionId == null || messages == null || messages.isClosed) return;

    final socket = _socket;
    if (socket == null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _openSocket();
      return;
    }
    if (_probeTimer != null) return;
    if (_ready) send({'type': 'ping'});
    _probeTimer = Timer(probeTimeout, () {
      _probeTimer = null;
      if (!identical(_socket, socket)) return;
      final subscription = _socketSubscription;
      _onSocketGone(
        socket,
        messages,
        const ServerException('Il server non risponde'),
      );
      unawaited(subscription?.cancel());
      unawaited(_closeQuietly(socket));
    });
  }

  static Future<void> _closeQuietly(RealtimeSocket socket) async {
    try {
      await socket.close(1000);
    } catch (_) {
      // Già chiuso o morto: niente da fare.
    }
  }

  void _startPing() {
    _stopPing();
    _pingTimer = Timer.periodic(pingInterval, (_) => send({'type': 'ping'}));
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _setStatus(RealtimeStatus status) {
    if (_status == status) return;
    _status = status;
    _statusChanges.add(status);
  }

  /// Manda un messaggio sulla connessione aperta. Ritorna `true` solo se il
  /// canale è aperto **e** il server ha già risposto `welcome`; `false`
  /// altrimenti (offline, in riconnessione, appena aperto) — nessuna coda:
  /// sta a chi chiama decidere (i datasource lo traducono in
  /// `ServerException`, quindi in `ConnectionFailure`: "non inviato").
  bool send(Map<String, dynamic> message) {
    final socket = _socket;
    if (socket == null || !_ready) return false;
    try {
      socket.add(jsonEncode(message));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Chiude la connessione per sempre (End): manda `end`, così il server
  /// chiude la sessione **subito** (presenza, richieste, match — il partner
  /// lo vede finire) invece di aspettare la grazia, e smette di riprovare.
  /// Chiude anche lo stream di [connect].
  ///
  /// **Best-effort con timeout**: se il socket è bloccato (rete caduta a
  /// metà) `close()` può non completarsi mai; dopo 2 s si abbandona comunque
  /// — in quel caso il server non riceve `end` e chiude la sessione da sé
  /// allo scadere della grazia. Chi chiama (`ProSession.end()`, il bottone
  /// End) non deve mai restare bloccato.
  ///
  /// Se End arriva **mentre si è in riconnessione** (il socket non è pronto
  /// e non può portare `end`) ma il server ha ancora la sessione nella
  /// grazia, `end` parte comunque su un socket d'addio a parte, appena
  /// questo è pronto (vedi [_sendFarewell]): il partner vede finire il
  /// match subito invece che dopo 45 s. Non blocca chi chiama.
  Future<void> disconnect() => _closeCurrent();

  Future<void> _closeCurrent() async {
    final socket = _socket;
    final subscription = _socketSubscription;
    final messages = _messages;
    final sessionId = _sessionId;
    final wasReady = _ready;
    // Un End arrivato mentre si era in riconnessione: il socket attuale non
    // può portare `end`, ma il server ha ancora la sessione (è nella
    // grazia) e il partner continuerebbe a vedere il match fino alla sua
    // scadenza. Si recapita con un socket "d'addio" (vedi [_sendFarewell]).
    final needsFarewell =
        !wasReady && sessionId != null && _serverGraceTimer != null;

    // Prima si azzera tutto (così `onDone` del socket non riprova), poi si
    // chiude.
    _sessionId = null;
    _messages = null;
    _socket = null;
    _socketSubscription = null;
    _ready = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopPing();
    _probeTimer?.cancel();
    _probeTimer = null;
    _serverGraceTimer?.cancel();
    _serverGraceTimer = null;
    _setStatus(RealtimeStatus.offline);
    if (needsFarewell) _sendFarewell(sessionId);

    try {
      await Future(() async {
        if (socket != null) {
          if (wasReady) socket.add(jsonEncode({'type': 'end'}));
          await socket.close(1000);
        }
        await subscription?.cancel();
      }).timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ignorato di proposito: vedi il commento di `disconnect`.
    }
    if (messages != null && !messages.isClosed) {
      unawaited(messages.close());
    }
  }

  /// Apre un socket a parte solo per dire `end` per [sessionId]: `hello`,
  /// al `welcome` manda `end` e chiude. Un tentativo solo, al massimo
  /// [farewellTimeout], senza toccare lo stato della connessione (che per
  /// chi la usa è già `offline`): se la rete non c'è, il server chiude la
  /// sessione da sé allo scadere della grazia, come prima.
  void _sendFarewell(String sessionId) {
    final RealtimeSocket socket;
    try {
      socket = _socketFactory(_endpoint());
    } catch (_) {
      return;
    }
    var finished = false;
    StreamSubscription<dynamic>? subscription;
    late final Timer timeout;
    void finish() {
      if (finished) return;
      finished = true;
      timeout.cancel();
      unawaited(subscription?.cancel());
      unawaited(_closeQuietly(socket));
    }

    timeout = Timer(farewellTimeout, finish);
    subscription = socket.stream.listen(
      (raw) {
        Object? decoded;
        try {
          decoded = jsonDecode(raw as String);
        } catch (_) {
          return;
        }
        if (decoded is! Map<String, dynamic> || decoded['type'] != 'welcome') {
          return;
        }
        try {
          socket.add(jsonEncode({'type': 'end'}));
        } catch (_) {
          // Chiuso nel frattempo: ci pensa la grazia del server.
        }
        finish();
      },
      onError: (Object _) {},
      onDone: finish,
      cancelOnError: false,
    );
    socket.ready.then((_) {
      if (finished) return;
      try {
        socket.add(jsonEncode({'type': 'hello', 'secret': sessionId}));
      } catch (_) {
        finish();
      }
    }, onError: (Object _) => finish());
  }
}
