import 'dart:async';
import 'dart:developer' as developer;

import 'package:threemojo_server/src/block_store.dart';
import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/encounter_proposal.dart';
import 'package:threemojo_server/src/encounter_store.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/moderation_records.dart';
import 'package:threemojo_server/src/moderation_store.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/presence_profile.dart';
import 'package:threemojo_server/src/report_reason.dart';
import 'package:threemojo_server/src/selfie_validator.dart';
import 'package:threemojo_server/src/session_lifecycle.dart';
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
///
/// **Blocca e Segnala** (`block`, `report`): il blocco vale nei due sensi
/// per tutta la vita della sessione di chi blocca (`BlockStore`); segnalare
/// implica bloccare, conta per la chiusura automatica (`ModerationStore`) e
/// aggiorna il record di moderazione cifrato (`ModerationRecordStore`) —
/// l'unico dato che il server conserva oltre le sessioni. Vedi
/// [_applyBlock] per cosa vede chi viene bloccato.
class RealtimeMessageHandler {
  RealtimeMessageHandler({
    required SessionStore sessions,
    required EncounterStore encounters,
    required ConnectionHub hub,
    required PaywallStore paywall,
    required HotspotStore hotspots,
    BlockStore? blocks,
    ModerationStore? moderation,
    ModerationRecordStore? records,
    SessionLifecycle? lifecycle,
    DateTime Function()? now,
  }) : _sessions = sessions,
       _encounters = encounters,
       _hub = hub,
       _paywall = paywall,
       _hotspots = hotspots,
       _blocks = blocks ?? BlockStore.instance,
       _moderation = moderation ?? ModerationStore.instance,
       _records = records ?? ModerationRecordStore.instance,
       _lifecycleOverride = lifecycle,
       _now = now ?? DateTime.now;

  static final RealtimeMessageHandler instance = RealtimeMessageHandler(
    sessions: SessionStore.instance,
    encounters: EncounterStore.instance,
    hub: ConnectionHub.instance,
    paywall: PaywallStore.instance,
    hotspots: HotspotStore.instance,
    blocks: BlockStore.instance,
    moderation: ModerationStore.instance,
    records: ModerationRecordStore.instance,
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

  /// La risposta al challenge della verifica del dispositivo
  /// (`attestation`): un attestation object App Attest è ~8 KB in base64, un
  /// token Play Integrity qualche KB (vedi `AttestationEvidence`).
  static const maxAttestationChars = 40 * 1024;

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
    'attestation' => maxAttestationChars,
    _ => maxOtherMessageChars,
  };

  final SessionStore _sessions;
  final EncounterStore _encounters;
  final ConnectionHub _hub;
  final PaywallStore _paywall;
  final HotspotStore _hotspots;
  final BlockStore _blocks;
  final ModerationStore _moderation;
  final ModerationRecordStore _records;
  final SessionLifecycle? _lifecycleOverride;
  final DateTime Function() _now;

  /// Chi chiude una sessione segnalata: quello iniettato (test) o il
  /// singleton, letto solo quando serve.
  SessionLifecycle get _lifecycle =>
      _lifecycleOverride ?? SessionLifecycle.instance;

  /// Gestisce un messaggio già decodificato di [sessionId] (id interno).
  /// `hello` ed `end` li gestisce `SocketSession`, non arrivano qui.
  /// [clientIp] è l'IP del socket (vuoto se ignoto): serve solo alla soglia
  /// della chiusura automatica per segnalazioni, mai salvato.
  void handle(
    String sessionId,
    Map<String, dynamic> message, {
    String clientIp = '',
  }) {
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
      case 'block':
        _handleBlock(sessionId, message);
      case 'report':
        _handleReport(sessionId, message, clientIp: clientIp);
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

    final tokenBefore = _sessions.unlockTokenFor(sessionId);
    final outcome = _sessions.upsertPosition(
      sessionId: sessionId,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      profile: PresenceProfile.fromJson(message),
      selfieBase64: selfie,
      unlockToken: unlockToken,
    );
    switch (outcome) {
      case PresenceOutcome.accepted:
        _hub.broadcastNearbyUpdates();
      case PresenceOutcome.tooSoon:
        // Posizione ignorata in silenzio (limite di frequenza, vedi
        // `SessionStore.minPositionInterval`): niente rifiuto, il client
        // può legittimamente mandarne di più. Si ricalcola solo se è
        // cambiato qualcos'altro che la presenza porta (sblocco, selfie).
        if (tokenBefore != unlockToken || selfie.isNotEmpty) {
          _hub.broadcastNearbyUpdates();
        }
      case PresenceOutcome.invalidCoordinates ||
          PresenceOutcome.implausibleMovement:
        _reject(sessionId, 'presence', outcome.name);
    }
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

    // Un blocco (in uno dei due sensi) toglie la persona dalla lista:
    // `notNearby`, come per chi è uscito.
    final nearby = _sessions.nearbyPeople(
      sessionId: sessionId,
      radiusMeters: ConnectionHub.radiusMeters,
      hotspotStore: _hotspots,
      paywallStore: _paywall,
      blockStore: _blocks,
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
        // Mancante (client vecchi) o sconosciuta → quella di ripiego.
        proposal: EncounterProposal.parse(message['proposal']),
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

  /// La sessione dietro [personId] (pseudonimo che [sessionId] ha
  /// ricevuto), o `null` se non si risolve o è [sessionId] stessa.
  String? _resolvePerson(String sessionId, Object? personId) {
    if (personId is! String || personId.isEmpty) return null;
    final target = _hub.pseudonyms.resolve(
      viewerId: sessionId,
      pseudonym: personId,
    );
    return target == sessionId ? null : target;
  }

  Map<String, dynamic> _personExtra(Object? personId) => {
    if (personId is String && personId.length <= 64) 'personId': personId,
  };

  void _handleBlock(String sessionId, Map<String, dynamic> message) {
    final personId = message['personId'];
    final target = _resolvePerson(sessionId, personId);
    if (target == null) {
      _reject(sessionId, 'block', 'unknownPerson', _personExtra(personId));
      return;
    }
    _applyBlock(blockerId: sessionId, blockedId: target);
  }

  /// Segnalare implica bloccare. Il blocco si applica anche oltre il limite
  /// di segnalazioni (`tooManyReports`); un motivo fuori lista invece non
  /// fa nulla (`invalidReason`).
  void _handleReport(
    String sessionId,
    Map<String, dynamic> message, {
    required String clientIp,
  }) {
    const action = 'report';
    final personId = message['personId'];
    final extra = _personExtra(personId);
    final reason = ReportReason.parse(message['reason']);
    if (reason == null) {
      _reject(sessionId, action, 'invalidReason', extra);
      return;
    }
    final target = _resolvePerson(sessionId, personId);
    if (target == null) {
      _reject(sessionId, action, 'unknownPerson', extra);
      return;
    }

    _applyBlock(blockerId: sessionId, blockedId: target);
    final outcome = _moderation.report(
      reporterId: sessionId,
      reporterIp: clientIp,
      reportedId: target,
      reason: reason,
      selfieBase64: _sessions.selfieBase64For(target) ?? '',
    );
    switch (outcome.result) {
      case ReportResult.tooManyReports:
        _reject(sessionId, action, 'tooManyReports', extra);
        return;
      case ReportResult.duplicate:
        return;
      case ReportResult.accepted:
        _saveRecord(outcome.tally!);
        if (outcome.shouldAutoClose) _lifecycle.closeForModeration(target);
    }
  }

  /// Aggiorna il record di moderazione in background: un disco lento o
  /// pieno non deve rallentare né far cadere il socket.
  void _saveRecord(ReportTally tally) {
    final record = ModerationRecord(
      id: tally.recordId,
      createdAt: ModerationRecord.roundToMinute(tally.createdAt),
      updatedAt: ModerationRecord.roundToMinute(_now()),
      reasons: {
        for (final entry in tally.reasons.entries) entry.key.name: entry.value,
      },
      reportCount: tally.reporters.length,
      autoClosed: tally.autoClosed,
      selfieBase64: tally.selfieBase64,
    );
    unawaited(
      _records.save(record).catchError((Object error, StackTrace stackTrace) {
        developer.log(
          'Salvataggio del record di moderazione fallito',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  /// [blockerId] blocca [blockedId]: da ora i due non si vedono più in
  /// "Vicinanze", nessuna richiesta né chat passa tra loro, per tutta la
  /// vita della sessione di chi blocca (anche attraverso grazia e
  /// riconnessioni: vale sugli id interni, vedi `BlockStore`).
  ///
  /// **Cosa vede chi è bloccato**: esattamente ciò che vedrebbe se l'altro
  /// avesse premuto End — gli stessi passi di `SessionLifecycle.endNow`:
  /// la richiesta pendente tra loro diventa `cancelled` e il match `ended`
  /// nel suo snapshot normale (l'app dice "l'altra persona è uscita"), poi
  /// le richieste tra i due spariscono; l'altro sparisce dalle sue
  /// "Vicinanze" (entro la finestra di 5 s per osservatore,
  /// `ConnectionHub.nearbyPushMinInterval`); e lo pseudonimo con cui lo
  /// vedeva non si risolve più, quindi ogni azione verso di lui fallisce
  /// come verso chi è uscito (richiesta `notNearby`, chat `notDelivered`,
  /// blocco/segnalazione `unknownPerson`). Limite: con una seconda sessione
  /// o un amico lì vicino potrebbe accorgersi che l'altro è ancora online.
  void _applyBlock({required String blockerId, required String blockedId}) {
    _blocks.block(blockerId, blockedId);
    final affected = _encounters.closeAllBetween(blockerId, blockedId);
    if (affected.isNotEmpty) _hub.pushEncounterSnapshot(blockedId);
    _encounters.forgetPair(blockerId, blockedId);
    _hub
      ..pseudonyms.forgetPair(viewerId: blockedId, targetId: blockerId)
      ..pushEncounterSnapshot(blockerId)
      ..broadcastNearbyUpdates();
  }
}
