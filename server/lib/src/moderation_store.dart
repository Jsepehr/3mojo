import 'dart:io';
import 'dart:math';

import 'package:threemojo_server/src/report_reason.dart';

/// Le soglie delle misure automatiche contro chi viene segnalato (vedi
/// [ModerationStore]), lette dalle variabili d'ambiente.
class ModerationConfig {
  const ModerationConfig({
    this.autoCloseReports = defaultAutoCloseReports,
    this.autoCloseMinIps = defaultAutoCloseMinIps,
    this.cooldown = defaultCooldown,
  });

  /// Le soglie da [environment]; un valore mancante, non intero o fuori
  /// scala lascia il predefinito.
  factory ModerationConfig.fromEnvironment(Map<String, String> environment) {
    int? read(String name, {required int min}) {
      final parsed = int.tryParse(environment[name]?.trim() ?? '');
      return parsed != null && parsed >= min ? parsed : null;
    }

    final cooldownMinutes = read(cooldownEnvironmentVariable, min: 0);
    return ModerationConfig(
      autoCloseReports:
          read(autoCloseReportsEnvironmentVariable, min: 1) ??
          defaultAutoCloseReports,
      autoCloseMinIps:
          read(autoCloseMinIpsEnvironmentVariable, min: 1) ??
          defaultAutoCloseMinIps,
      cooldown: cooldownMinutes == null
          ? defaultCooldown
          : Duration(minutes: cooldownMinutes),
    );
  }

  static const defaultAutoCloseReports = 3;
  static const defaultAutoCloseMinIps = 2;
  static const defaultCooldown = Duration(minutes: 30);

  static const autoCloseReportsEnvironmentVariable =
      'MODERATION_AUTO_CLOSE_REPORTS';
  static const autoCloseMinIpsEnvironmentVariable =
      'MODERATION_AUTO_CLOSE_MIN_IPS';
  static const cooldownEnvironmentVariable = 'MODERATION_COOLDOWN_MINUTES';

  /// Da quante sessioni **diverse** deve arrivare una segnalazione perché
  /// la sessione segnalata venga chiusa da sola.
  final int autoCloseReports;

  /// Da quanti IP diversi devono arrivare quelle segnalazioni (vedi
  /// [ModerationStore.report]).
  final int autoCloseMinIps;

  /// Per quanto, dopo una chiusura automatica, gli IP della sessione chiusa
  /// non possono fare un nuovo Start. [Duration.zero] = spento.
  final Duration cooldown;
}

/// Lo stato in RAM delle segnalazioni ricevute da una sessione.
class ReportTally {
  ReportTally._({
    required this.recordId,
    required this.createdAt,
    required this.selfieBase64,
  });

  /// L'id casuale del record di moderazione (`ModerationRecordStore`):
  /// non derivato da nulla della sessione, e il legame "sessione → record"
  /// vive solo qui, in RAM, finché la sessione segnalata è viva.
  final String recordId;
  final DateTime createdAt;

  /// Il selfie della persona segnalata **alla prima segnalazione** (già
  /// ripulito dai metadati da `SelfieValidator`): è ciò che vedrà chi
  /// revisiona.
  final String selfieBase64;

  /// Id interni di chi ha segnalato (mai nel record).
  final Set<String> reporters = {};

  /// IP di chi ha segnalato, solo per la soglia della chiusura automatica
  /// (mai nel record, nemmeno come hash).
  final Set<String> reporterIps = {};
  final Map<ReportReason, int> reasons = {};
  bool autoClosed = false;
}

/// Esito di [ModerationStore.report].
enum ReportResult {
  /// Contata: il record va aggiornato.
  accepted,

  /// La stessa sessione aveva già segnalato la stessa persona: accettata in
  /// silenzio, non conta né per il limite né per la soglia.
  duplicate,

  /// Chi segnala ha già fatto [ModerationStore.maxReportsPerSession]
  /// segnalazioni in questa sessione: non contata.
  tooManyReports,
}

class ReportOutcome {
  const ReportOutcome(this.result, {this.tally, this.shouldAutoClose = false});

  final ReportResult result;

  /// Lo stato aggiornato della sessione segnalata (per [ReportResult.accepted]
  /// e [ReportResult.duplicate]).
  final ReportTally? tally;

  /// La soglia è appena stata raggiunta: la sessione segnalata va chiusa
  /// (`SessionLifecycle.closeForModeration`). Scatta una volta sola.
  final bool shouldAutoClose;
}

/// Segnalazioni e misure automatiche, **solo in RAM** e solo per la vita
/// delle sessioni coinvolte ([forgetSession]): chi ha segnalato chi, da
/// quali IP, con quali motivi. Di tutto questo sopravvive alla sessione solo
/// il record cifrato di `ModerationRecordStore` (senza id, pseudonimi né IP)
/// e, per [ModerationConfig.cooldown], l'IP in cooldown.
///
/// **Chiusura automatica**: quando una sessione riceve segnalazioni da
/// almeno [ModerationConfig.autoCloseReports] sessioni diverse, provenienti
/// da almeno [ModerationConfig.autoCloseMinIps] IP diversi, va chiusa. La
/// condizione sugli IP rende più difficile che una sola persona con più
/// telefoni sulla stessa rete faccia chiudere qualcuno; un IP vuoto non è
/// un'informazione: se **nessun** segnalatore ha un IP noto la condizione è
/// ignorata (conta solo il numero di sessioni). Dietro un reverse proxy
/// senza `TRUSTED_PROXY` tutti sembrano lo stesso IP (quello del proxy): la
/// condizione dei 2 IP non scatta mai.
///
/// **Cooldown**: dopo una chiusura automatica gli IP visti dalla sessione
/// chiusa non possono fare un nuovo Start per [ModerationConfig.cooldown]
/// (vedi `SessionLifecycle.hello`, che risponde `rateLimited`). Rischio
/// noto: un IP può essere condiviso da molte persone (Wi-Fi di un locale,
/// CGNAT degli operatori mobili) — per quel tempo anche gli altri sulla
/// stessa rete non possono fare uno Start nuovo (le sessioni già aperte e
/// le riconnessioni non sono toccate). Per questo il cooldown è breve e
/// configurabile, e `0` lo spegne.
///
/// Limite per chi segnala: [maxReportsPerSession] segnalazioni a sessione,
/// contro chi segnalasse tutti quelli che vede.
class ModerationStore {
  ModerationStore._({
    DateTime Function()? now,
    this.config = const ModerationConfig(),
    Random? random,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  /// Solo per i test: orologio controllabile (e, volendo, altre soglie).
  factory ModerationStore.withClock(
    DateTime Function() now, {
    ModerationConfig config = const ModerationConfig(),
  }) => ModerationStore._(now: now, config: config);

  static final ModerationStore instance = ModerationStore._(
    config: ModerationConfig.fromEnvironment(Platform.environment),
  );

  /// Quante segnalazioni (contate) può fare una sessione. **Allineata** con
  /// `ReportPersonUseCase.maxReportsPerSession` nell'app: cambiarle insieme.
  static const maxReportsPerSession = 5;

  final DateTime Function() _now;
  final Random _random;
  final ModerationConfig config;

  final Map<String, ReportTally> _tallies = {};
  final Map<String, int> _reportsMadeBy = {};
  final Map<String, DateTime> _cooldownUntilByIp = {};

  /// Registra che [reporterId] (dall'IP [reporterIp], vuoto se ignoto)
  /// segnala [reportedId] per [reason]. [selfieBase64] è il selfie attuale
  /// della persona segnalata: conta solo alla prima segnalazione.
  ReportOutcome report({
    required String reporterId,
    required String reporterIp,
    required String reportedId,
    required ReportReason reason,
    String selfieBase64 = '',
  }) {
    final existing = _tallies[reportedId];
    if (existing != null && existing.reporters.contains(reporterId)) {
      return ReportOutcome(ReportResult.duplicate, tally: existing);
    }
    final made = _reportsMadeBy[reporterId] ?? 0;
    if (made >= maxReportsPerSession) {
      return const ReportOutcome(ReportResult.tooManyReports);
    }
    _reportsMadeBy[reporterId] = made + 1;

    final tally =
        existing ??
        ReportTally._(
          recordId: _newRecordId(),
          createdAt: _now(),
          selfieBase64: selfieBase64,
        );
    _tallies[reportedId] = tally;
    tally.reporters.add(reporterId);
    if (reporterIp.isNotEmpty) tally.reporterIps.add(reporterIp);
    tally.reasons.update(reason, (count) => count + 1, ifAbsent: () => 1);

    final enoughIps =
        tally.reporterIps.isEmpty ||
        tally.reporterIps.length >= config.autoCloseMinIps;
    final shouldAutoClose =
        !tally.autoClosed &&
        tally.reporters.length >= config.autoCloseReports &&
        enoughIps;
    if (shouldAutoClose) tally.autoClosed = true;
    return ReportOutcome(
      ReportResult.accepted,
      tally: tally,
      shouldAutoClose: shouldAutoClose,
    );
  }

  /// Lo stato delle segnalazioni ricevute da [reportedId], se ce ne sono.
  ReportTally? tallyFor(String reportedId) => _tallies[reportedId];

  /// Blocca i nuovi Start da [ip] per [ModerationConfig.cooldown].
  void startCooldown(String ip) {
    if (ip.isEmpty || config.cooldown <= Duration.zero) return;
    _cooldownUntilByIp[ip] = _now().add(config.cooldown);
  }

  /// `true` se da [ip] non si può fare un nuovo Start ora.
  bool isInCooldown(String ip) {
    final now = _now();
    _cooldownUntilByIp.removeWhere((_, until) => !now.isBefore(until));
    return _cooldownUntilByIp.containsKey(ip);
  }

  /// Alla fine di [sessionId]: dimentica le segnalazioni che ha ricevuto
  /// (il record su disco resta, ma nessuno sa più a quale sessione
  /// apparteneva) e quante ne ha fatte; nelle segnalazioni fatte ad altri il
  /// suo id è sostituito da un segnaposto casuale (il conteggio resta: le
  /// segnalazioni restano valide, ma il suo id non sopravvive).
  void forgetSession(String sessionId) {
    _tallies.remove(sessionId);
    _reportsMadeBy.remove(sessionId);
    for (final tally in _tallies.values) {
      if (tally.reporters.remove(sessionId)) {
        tally.reporters.add('ended-${_newRecordId()}');
      }
    }
  }

  /// 128 bit casuali in esadecimale (vedi `ModerationRecordStore.isValidId`).
  String _newRecordId() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
