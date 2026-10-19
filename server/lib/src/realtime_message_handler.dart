import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/encounter_store.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/presence_profile.dart';
import 'package:threemojo_server/src/selfie_validator.dart';
import 'package:threemojo_server/src/session_store.dart';

/// Interpreta i messaggi di un client **già autenticato** (dopo `hello`,
/// vedi `SocketSession`) e applica le regole del server. Mai fidarsi del
/// client: ogni campo è controllato (tipo, lunghezza, valori ammessi) prima
/// di toccare qualsiasi store, e ogni rifiuto che il client può voler
/// raccontare all'utente torna come
/// `{"type": "rejected", "action": ..., "reason": ...}`.
///
/// Gli id delle altre persone che il client manda (`toPersonId`) sono
/// pseudonimi per osservatore (vedi `Pseudonyms`): qui vengono ritradotti
/// negli id interni, e uno pseudonimo che quel client non ha mai ricevuto
/// non si risolve.
class RealtimeMessageHandler {
  RealtimeMessageHandler({
    required SessionStore sessions,
    required EncounterStore encounters,
    required ConnectionHub hub,
    required PaywallStore paywall,
    required HotspotStore hotspots,
  }) : _sessions = sessions,
       _encounters = encounters,
       _hub = hub,
       _paywall = paywall,
       _hotspots = hotspots;

  static final RealtimeMessageHandler instance = RealtimeMessageHandler(
    sessions: SessionStore.instance,
    encounters: EncounterStore.instance,
    hub: ConnectionHub.instance,
    paywall: PaywallStore.instance,
    hotspots: HotspotStore.instance,
  );

  /// Una presenza porta (solo la prima volta) il selfie: ~310 KB in base64
  /// al massimo (vedi `SelfieValidator.maxBytes`), più il resto.
  static const maxPresenceChars = 320 * 1024;

  /// Soglia **di sicurezza** per un frame di chat, molto più alta del
  /// testo ammesso ([maxChatTextLength] più la busta JSON, anche con ogni
  /// carattere escapato `\uXXXX`): un testo troppo lungo ma sotto questa
  /// soglia non chiude il socket, torna `rejected` `invalidText` (vedi
  /// `_handleChatMessage`) e il client lo può raccontare. Solo un frame
  /// oltre questa soglia (un client rotto o malevolo) chiude il socket
  /// (4009).
  static const maxChatMessageChars = 16 * 1024;

  /// Qualsiasi altro messaggio (hello, richieste, ping, end).
  static const maxOtherMessageChars = 1024;

  /// Lunghezza massima del testo di un messaggio di chat, in unità UTF-16
  /// (`String.length` di Dart). **Allineata** con
  /// `SendMessageUseCase.maxTextLength` nell'app: cambiarle insieme.
  static const maxChatTextLength = 1000;

  static const _maxUnlockTokenLength = 64;
  static const _maxClientMessageIdLength = 64;

  /// Il limite di dimensione per un messaggio di tipo [type] (vedi le
  /// costanti sopra).
  static int maxCharsFor(Object? type) => switch (type) {
    'presence' => maxPresenceChars,
    'chatMessage' => maxChatMessageChars,
    _ => maxOtherMessageChars,
  };

  final SessionStore _sessions;
  final EncounterStore _encounters;
  final ConnectionHub _hub;
  final PaywallStore _paywall;
  final HotspotStore _hotspots;

  /// Gestisce un messaggio già decodificato di [sessionId] (id interno).
  /// `hello` ed `end` li gestisce `SocketSession`, non arrivano qui.
  void handle(String sessionId, Map<String, dynamic> message) {
    switch (message['type']) {
      case 'ping':
        // "Sono vivo": `lastSeen` è già aggiornato da chi chiama. Il `pong`
        // serve al client per accorgersi di un socket morto senza che
        // nessuno l'abbia chiuso (es. l'app torna in primo piano dopo che
        // il telefono ha cambiato rete): se non arriva entro pochi secondi,
        // riapre la connessione.
        _hub.sendTo(sessionId, const {'type': 'pong'});
      case 'presence':
        _handlePresence(sessionId, message);
      case 'sendEncounterRequest':
        _handleSendEncounterRequest(sessionId, message);
      case 'respondToEncounterRequest':
        _handleRespondToEncounterRequest(sessionId, message);
      case 'endMatch':
        _handleEndMatch(sessionId, message);
      case 'chatMessage':
        _handleChatMessage(sessionId, message);
    }
  }

  void _reject(
    String sessionId,
    String action,
    String reason, [
    Map<String, dynamic> extra = const {},
  ]) {
    _hub.sendTo(sessionId, {
      'type': 'rejected',
      'action': action,
      'reason': reason,
      ...extra,
    });
  }

  void _handlePresence(String sessionId, Map<String, dynamic> message) {
    final lat = message['lat'];
    final lng = message['lng'];
    if (lat is! num || lng is! num) {
      _reject(sessionId, 'presence', 'invalidCoordinates');
      return;
    }

    // Il selfie conta solo finché la sessione non ne ha uno: è fissato alla
    // nascita come il profilo, quindi le presenze successive possono (e
    // dovrebbero) non rimandarlo.
    var selfie = '';
    final rawSelfie = message['selfieBase64'];
    final needsSelfie =
        !_sessions.contains(sessionId) ||
        (_sessions.selfieBase64For(sessionId)?.isEmpty ?? true);
    if (needsSelfie && rawSelfie is String && rawSelfie.isNotEmpty) {
      final sanitized = SelfieValidator.sanitizeBase64(rawSelfie);
      if (sanitized == null) {
        _reject(sessionId, 'presence', 'invalidSelfie');
        return;
      }
      selfie = sanitized;
    }

    final rawToken = message['unlockToken'];
    final unlockToken =
        rawToken is String && rawToken.length <= _maxUnlockTokenLength
        ? rawToken
        : '';

    final outcome = _sessions.upsertPosition(
      sessionId: sessionId,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      profile: PresenceProfile.fromJson(message),
      selfieBase64: selfie,
      unlockToken: unlockToken,
    );
    if (outcome != PresenceOutcome.accepted) {
      _reject(sessionId, 'presence', outcome.name);
      return;
    }
    _hub.broadcastNearbyUpdates();
  }

  /// Una richiesta parte solo se il destinatario è online, diverso dal
  /// mittente, **nella lista "Vicinanze" del mittente in questo momento**
  /// (raggio o hotspot, compatibilità reciproca, permanenza) e non bloccato
  /// dal paywall per lui — più le regole di `EncounterStore.sendRequest`
  /// (niente doppioni per la coppia, nessuno già in match, tetti alle
  /// pendenti). Senza, chiunque avesse uno pseudonimo valido potrebbe
  /// mandare richieste a chi non vede più o a chi non ha mai sbloccato.
  void _handleSendEncounterRequest(
    String sessionId,
    Map<String, dynamic> message,
  ) {
    const action = 'sendEncounterRequest';
    final toPersonId = message['toPersonId'];
    if (toPersonId is! String || toPersonId.isEmpty) return;
    final extra = {'toPersonId': toPersonId};

    final toSessionId = _hub.pseudonyms.resolve(
      viewerId: sessionId,
      pseudonym: toPersonId,
    );
    if (toSessionId == null) {
      _reject(
        sessionId,
        action,
        EncounterRejectionReason.notNearby.name,
        extra,
      );
      return;
    }
    if (toSessionId == sessionId) {
      _reject(sessionId, action, EncounterRejectionReason.self.name, extra);
      return;
    }
    if (!_sessions.isOnline(toSessionId) || !_hub.isConnected(toSessionId)) {
      _reject(
        sessionId,
        action,
        EncounterRejectionReason.notOnline.name,
        extra,
      );
      return;
    }

    final nearby = _sessions.nearbyPeople(
      sessionId: sessionId,
      radiusMeters: ConnectionHub.radiusMeters,
      hotspotStore: _hotspots,
      paywallStore: _paywall,
    );
    final target = nearby
        ?.where((person) => person.sessionId == toSessionId)
        .firstOrNull;
    if (target == null) {
      _reject(
        sessionId,
        action,
        EncounterRejectionReason.notNearby.name,
        extra,
      );
      return;
    }
    if (target.locked) {
      _reject(sessionId, action, EncounterRejectionReason.locked.name, extra);
      return;
    }

    try {
      _encounters.sendRequest(
        fromSessionId: sessionId,
        toSessionId: toSessionId,
      );
    } on EncounterRejected catch (rejection) {
      _reject(sessionId, action, rejection.reason.name, extra);
      return;
    }
    _hub
      ..pushEncounterSnapshot(sessionId)
      ..pushEncounterSnapshot(toSessionId);
  }

  void _handleRespondToEncounterRequest(
    String sessionId,
    Map<String, dynamic> message,
  ) {
    const action = 'respondToEncounterRequest';
    final requestId = message['requestId'];
    final accepted = message['accepted'];
    if (requestId is! String || accepted is! bool) return;

    final ({EncounterRequest request, List<EncounterRequest> alsoCancelled})
    result;
    try {
      result = _encounters.respondToRequest(
        requestId: requestId,
        accepted: accepted,
        bySessionId: sessionId,
      );
    } on EncounterRejected catch (rejection) {
      _reject(sessionId, action, rejection.reason.name, {
        'requestId': requestId,
      });
      return;
    } on ArgumentError {
      // Id sconosciuto, non destinatario, non più pendente: non c'è nulla
      // da raccontare all'utente, lo snapshot che ha è già quello giusto.
      return;
    }

    final touchedSessionIds = {
      result.request.fromSessionId,
      result.request.toSessionId,
      for (final cancelled in result.alsoCancelled) ...[
        cancelled.fromSessionId,
        cancelled.toSessionId,
      ],
    };
    for (final id in touchedSessionIds) {
      _hub.pushEncounterSnapshot(id);
    }
  }

  void _handleEndMatch(String sessionId, Map<String, dynamic> message) {
    final requestId = message['requestId'];
    if (requestId is! String) return;

    final EncounterRequest request;
    try {
      request = _encounters.endMatch(requestId, bySessionId: sessionId);
    } on ArgumentError {
      return;
    }

    _hub
      ..pushEncounterSnapshot(request.fromSessionId)
      ..pushEncounterSnapshot(request.toSessionId);
  }

  /// Inoltra solo verso uno pseudonimo che il mittente conosce, solo con un
  /// match attivo (vedi `ConnectionHub.relayChatMessage`). Se il messaggio
  /// non parte, il mittente lo sa (`rejected`, con il suo
  /// `clientMessageId` se l'ha mandato): così l'app può mostrarlo come "non
  /// inviato" invece di far credere che sia arrivato.
  void _handleChatMessage(String sessionId, Map<String, dynamic> message) {
    const action = 'chatMessage';
    final toPersonId = message['toPersonId'];
    final text = message['text'];
    final clientMessageId = message['clientMessageId'];
    final extra = <String, dynamic>{
      if (clientMessageId is String &&
          clientMessageId.length <= _maxClientMessageIdLength)
        'clientMessageId': clientMessageId,
    };
    if (toPersonId is! String || text is! String) return;
    if (text.trim().isEmpty || text.length > maxChatTextLength) {
      _reject(sessionId, action, 'invalidText', extra);
      return;
    }

    final toSessionId = _hub.pseudonyms.resolve(
      viewerId: sessionId,
      pseudonym: toPersonId,
    );
    final delivered =
        toSessionId != null &&
        _hub.relayChatMessage(
          fromSessionId: sessionId,
          toSessionId: toSessionId,
          text: text,
        );
    if (!delivered) _reject(sessionId, action, 'notDelivered', extra);
  }
}
