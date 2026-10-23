import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:threemojo_server/src/attestation/attestation_challenge.dart';
import 'package:threemojo_server/src/attestation/attestation_gate.dart';
import 'package:threemojo_server/src/realtime_message_handler.dart';
import 'package:threemojo_server/src/rate_limiters.dart';
import 'package:threemojo_server/src/session_credentials.dart';
import 'package:threemojo_server/src/session_lifecycle.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Un singolo socket WebSocket, dall'apertura alla chiusura. Separato dalla
/// route `/ws` così si può provare con due `StreamController` al posto di
/// un vero socket.
///
/// 1. **Autenticazione col primo messaggio**: `{"type": "hello", "secret":
///    ...}` entro [helloTimeout], altrimenti il socket viene chiuso senza
///    aver registrato nulla. Il segreto non passa più dall'URL (finiva nei
///    log di proxy e provider). Dopo un hello valido: `welcome` (vedi
///    `SessionLifecycle.attach`).
/// 1b. **Verifica del dispositivo** (`AttestationGate`, spenta di default):
///    se è attiva e l'hello aprirebbe una sessione **nuova** (non una
///    riconnessione di una sessione viva), prima del `welcome` il server
///    manda `{"type": "challenge", "nonce": ...}` e aspetta entro
///    [attestationTimeout] `{"type": "attestation", ...}` legata a quel
///    nonce. Durante la verifica (asincrona: Google) gli altri messaggi del
///    socket restano in coda. Esito: `welcome`, oppure `error`
///    `attestationRequired` (4011) / `rateLimited` (4008) e chiusura. Nulla
///    della sessione viene registrato prima dell'esito.
/// 2. **Limiti**: solo messaggi di testo; dimensione massima per tipo
///    (`RealtimeMessageHandler.maxCharsFor`, controllata prima di decodificare
///    il JSON quando possibile); un limite di messaggi al secondo per
///    connessione ([ConnectionRateLimiter]) — oltre si scarta, e chi
///    insiste viene chiuso.
/// 3. **Fine**: `{"type": "end"}` chiude la sessione subito; ogni altra
///    chiusura avvia il periodo di grazia (`SessionLifecycle.detach`).
///
/// Nessuna eccezione esce da qui: un messaggio malformato di un client non
/// deve poter far cadere il server per tutti.
class SocketSession {
  SocketSession({
    required Stream<dynamic> incoming,
    required StreamSink<dynamic> outgoing,
    required String clientIp,
    SessionLifecycle? lifecycle,
    RealtimeMessageHandler? handler,
    ConnectionRateLimiter? rateLimiter,
    AttestationGate? attestation,
    this.helloTimeout = defaultHelloTimeout,
    this.attestationTimeout = defaultAttestationTimeout,
  }) : _incoming = incoming,
       _outgoing = outgoing,
       _clientIp = clientIp,
       _lifecycle = lifecycle ?? SessionLifecycle.instance,
       _handler = handler ?? RealtimeMessageHandler.instance,
       _rateLimiter = rateLimiter ?? ConnectionRateLimiter(),
       _attestation = attestation ?? AttestationGate.instance;

  static const defaultHelloTimeout = Duration(seconds: 10);

  /// Quanto si aspetta la risposta al challenge: un po' più della validità
  /// del nonce (`AttestationChallenge.defaultTtl`), così una risposta in
  /// ritardo è "challenge scaduto" e non un silenzio.
  static const defaultAttestationTimeout = Duration(seconds: 25);

  /// Codici di chiusura (intervallo 4000-4999, riservato alle applicazioni).
  static const closeHelloRequired = 4001;
  static const closeInvalidSecret = 4002;
  static const closeUnsupportedData = 4003;
  static const closeRateLimited = 4008;
  static const closeTooLarge = 4009;

  /// Sessione nuova senza un'attestazione valida (`ATTESTATION_MODE=enforce`).
  static const closeAttestationRequired = 4011;
  static const closeTooManyMessages = 4029;

  /// Dopo quanti messaggi scartati di fila per il limite di frequenza il
  /// socket viene chiuso.
  static const maxConsecutiveDropped = 50;

  final Stream<dynamic> _incoming;
  final StreamSink<dynamic> _outgoing;
  final String _clientIp;
  final SessionLifecycle _lifecycle;
  final RealtimeMessageHandler _handler;
  final ConnectionRateLimiter _rateLimiter;
  final AttestationGate _attestation;
  final Duration helloTimeout;
  final Duration attestationTimeout;

  StreamSubscription<dynamic>? _subscription;
  Timer? _helloTimer;
  Timer? _attestationTimer;

  /// Il challenge mandato dopo un hello che aprirebbe una sessione nuova, e
  /// il segreto di quell'hello: la sessione nasce solo dopo l'esito.
  AttestationChallenge? _challenge;
  String? _pendingSecret;
  bool _verifying = false;
  String? _sessionId;
  bool _explicitEnd = false;
  bool _closed = false;
  int _consecutiveDropped = 0;

  /// L'id interno della sessione, dopo un hello valido.
  String? get sessionId => _sessionId;

  void start() {
    _helloTimer = Timer(helloTimeout, () {
      if (_sessionId == null) _close(closeHelloRequired, 'hello timeout');
    });
    _subscription = _incoming.listen(
      _onData,
      onError: (Object _) {},
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  void _onData(dynamic raw) {
    if (_closed) return;
    try {
      _process(raw);
    } catch (error, stackTrace) {
      developer.log(
        'Messaggio WebSocket non gestito',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _process(dynamic raw) {
    if (!_rateLimiter.tryConsume()) {
      _consecutiveDropped++;
      if (_consecutiveDropped >= maxConsecutiveDropped) {
        _close(closeTooManyMessages, 'too many messages');
      }
      return;
    }
    _consecutiveDropped = 0;

    if (raw is! String) {
      _close(closeUnsupportedData, 'text only');
      return;
    }
    if (raw.length > RealtimeMessageHandler.maxPresenceChars) {
      _close(closeTooLarge, 'message too large');
      return;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final type = decoded['type'];
    if (raw.length > RealtimeMessageHandler.maxCharsFor(type)) {
      _close(closeTooLarge, 'message too large');
      return;
    }

    final sessionId = _sessionId;
    if (sessionId == null) {
      if (_challenge == null) {
        _handleHello(type, decoded);
      } else if (type == 'attestation' && !_verifying) {
        _handleAttestation(decoded);
      } else {
        _close(closeHelloRequired, 'attestation required');
      }
      return;
    }

    _lifecycle.touch(sessionId);
    if (type == 'end') {
      _explicitEnd = true;
      _lifecycle.endNow(sessionId);
      return;
    }
    // Un'attestazione arrivata dopo che la modalità `log` ha già lasciato
    // passare per timeout: non serve più.
    if (type == 'hello' || type == 'attestation') return;
    _handler.handle(sessionId, decoded, clientIp: _clientIp);
  }

  void _handleHello(Object? type, Map<String, dynamic> message) {
    if (type != 'hello') {
      _close(closeHelloRequired, 'hello required');
      return;
    }
    final rawSecret = message['secret'];
    final secret = rawSecret is String ? rawSecret : null;
    if (_attestation.isActive &&
        SessionCredentials.isValidSecret(secret) &&
        !_lifecycle.wouldResume(secret)) {
      _sendChallenge(secret!);
      return;
    }
    _completeHello(secret);
  }

  /// Una sessione nuova con la verifica attiva: prima il challenge.
  void _sendChallenge(String secret) {
    _helloTimer?.cancel();
    final challenge = _attestation.issueChallenge();
    _challenge = challenge;
    _pendingSecret = secret;
    _send({
      'type': 'challenge',
      'nonce': challenge.nonce,
      'expiresInSeconds': challenge.ttl.inSeconds,
    });
    _attestationTimer = Timer(attestationTimeout, () {
      if (_closed || _verifying || _sessionId != null) return;
      _onAttestationDecision(_attestation.timedOut());
    });
  }

  void _handleAttestation(Map<String, dynamic> message) {
    _attestationTimer?.cancel();
    _verifying = true;
    // Gli altri messaggi aspettano l'esito (la verifica può chiamare Google).
    _subscription?.pause();
    unawaited(_verify(_challenge!, message));
  }

  Future<void> _verify(
    AttestationChallenge challenge,
    Map<String, dynamic> message,
  ) async {
    AttestationDecision decision;
    try {
      decision = await _attestation.evaluate(
        challenge: challenge,
        message: message,
        ip: _clientIp,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Verifica del dispositivo non gestita',
        error: error,
        stackTrace: stackTrace,
      );
      decision = AttestationDecision.deny;
    }
    _verifying = false;
    try {
      _onAttestationDecision(decision);
    } catch (error, stackTrace) {
      developer.log(
        'Hello dopo la verifica non gestito',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _subscription?.resume();
    }
  }

  void _onAttestationDecision(AttestationDecision decision) {
    if (_closed) return;
    switch (decision) {
      case AttestationDecision.allow:
        _completeHello(_pendingSecret);
      case AttestationDecision.deny:
        _sendError('attestationRequired');
        _close(closeAttestationRequired, 'attestation required');
      case AttestationDecision.rateLimited:
        _sendError('rateLimited');
        _close(closeRateLimited, 'rate limited');
    }
    _pendingSecret = null;
  }

  void _completeHello(String? secret) {
    final outcome = _lifecycle.hello(secret: secret, ip: _clientIp);
    switch (outcome) {
      case HelloInvalidSecret():
        _sendError('invalidSecret');
        _close(closeInvalidSecret, 'invalid secret');
      case HelloRateLimited():
        _sendError('rateLimited');
        _close(closeRateLimited, 'rate limited');
      case HelloAccepted(:final publicId, :final resumed):
        _helloTimer?.cancel();
        _sessionId = publicId;
        _lifecycle.attach(publicId, _outgoing, resumed: resumed, ip: _clientIp);
    }
  }

  void _sendError(String code) => _send({'type': 'error', 'code': code});

  void _send(Map<String, Object?> message) {
    try {
      _outgoing.add(jsonEncode(message));
    } catch (_) {
      // Socket già chiuso.
    }
  }

  void _close(int code, String reason) {
    if (_closed) return;
    _closed = true;
    _helloTimer?.cancel();
    _attestationTimer?.cancel();
    final sink = _outgoing;
    try {
      if (sink is WebSocketSink) {
        unawaited(sink.close(code, reason).catchError((Object _) {}));
      } else {
        unawaited(sink.close().catchError((Object _) {}));
      }
    } catch (_) {
      // Già chiuso.
    }
  }

  void _onDone() {
    _closed = true;
    _helloTimer?.cancel();
    _attestationTimer?.cancel();
    unawaited(_subscription?.cancel());
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      _lifecycle.detach(sessionId, _outgoing, explicitEnd: _explicitEnd);
    } catch (error, stackTrace) {
      developer.log(
        'Chiusura del socket non gestita',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
