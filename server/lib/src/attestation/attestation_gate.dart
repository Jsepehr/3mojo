import 'dart:async';
import 'dart:io';

import '../rate_limiters.dart';
import 'app_attest_verifier.dart';
import 'attestation_challenge.dart';
import 'attestation_config.dart';
import 'attestation_verifier.dart';
import 'fake_attestation_verifier.dart';
import 'play_integrity_api.dart';
import 'play_integrity_verifier.dart';

/// Com'è andata una verifica (per il log e le metriche: al client arriva
/// solo l'esito, vedi [AttestationDecision]).
enum AttestationOutcome {
  /// Attestazione valida per il challenge di questo socket.
  valid,

  /// Controllata e non valida (motivo nel log).
  invalid,

  /// Il client ha risposto senza attestazione (sul telefono non è
  /// riuscita, simulatore iOS, build vecchio) o con una forma sbagliata.
  missing,

  /// Il client non ha risposto al challenge in tempo.
  timeout,

  /// Challenge già usato o scaduto.
  expiredChallenge,

  /// Troppe attestazioni dallo stesso IP nell'ultimo minuto: non verificata.
  rateLimited,

  /// Piattaforma senza verificatore configurato.
  unsupportedPlatform,

  /// Verifica non riuscita per motivi nostri o di Google (rete, quota,
  /// credenziali): non si sa se l'attestazione è valida.
  unavailable,
}

/// Cosa fa `SocketSession` con il `hello` in sospeso.
enum AttestationDecision {
  /// La sessione può nascere.
  allow,

  /// `error` `attestationRequired` e chiusura (4011).
  deny,

  /// `error` `rateLimited` e chiusura (4008), come per troppi Start.
  rateLimited,
}

/// La **regola** della verifica del dispositivo, per le sessioni nuove
/// (le riconnessioni di una sessione viva non passano di qui):
/// - [AttestationMode.off]: non entra mai in gioco ([isActive] `false`);
/// - [AttestationMode.log]: verifica, scrive l'esito nel log e lascia
///   sempre passare;
/// - [AttestationMode.enforce]: passa solo [AttestationOutcome.valid]
///   (fail closed: anche "Google non risponde" è un rifiuto — altrimenti
///   basterebbe esaurire la nostra quota per far passare tutti).
///
/// Limiti: al più [maxPerIpPerMinute] attestazioni da verificare per IP al
/// minuto, al più [maxConcurrentVerifications] verifiche in corso insieme,
/// ognuna entro [verifyTimeout].
///
/// **Nessun dato dell'attestazione viene conservato**: token, keyId,
/// attestation object e verdetti esistono solo durante [evaluate]. Restano
/// in RAM solo i contatori per esito ([counts]) e, per [rateLimit], gli
/// orari delle ultime attestazioni per IP per un minuto. Il log contiene
/// solo modalità, piattaforma, esito e motivo — mai IP, token o keyId.
class AttestationGate {
  AttestationGate({
    required this.mode,
    Map<AttestationPlatform, AttestationVerifier> verifiers = const {},
    this.maxPerIpPerMinute = AttestationConfig.defaultMaxPerIpPerMinute,
    this.maxConcurrentVerifications = 32,
    this.verifyTimeout = const Duration(seconds: 10),
    this.challengeTtl = AttestationChallenge.defaultTtl,
    this.config,
    DateTime Function()? now,
    void Function(String line)? log,
  }) : _verifiers = verifiers,
       _now = now ?? DateTime.now,
       _log = log ?? stderr.writeln,
       rateLimit = SlidingWindowRateLimiter(
         maxActions: maxPerIpPerMinute,
         window: const Duration(minutes: 1),
         now: now,
       );

  /// Monta i verificatori dalla configurazione: una piattaforma senza
  /// configurazione completa non ha verificatore (→ `unsupportedPlatform`).
  factory AttestationGate.fromConfig(
    AttestationConfig config, {
    PlayIntegrityApi? playIntegrityApi,
    DateTime Function()? now,
    void Function(String line)? log,
  }) {
    final verifiers = <AttestationPlatform, AttestationVerifier>{};
    final android = config.playIntegrity;
    final ios = config.appAttest;
    if (config.mode != AttestationMode.off) {
      if (android != null) {
        verifiers[AttestationPlatform.android] = PlayIntegrityVerifier(
          packageName: android.packageName,
          api:
              playIntegrityApi ??
              PlayIntegrityApiImpl(
                packageName: android.packageName,
                serviceAccountJson: android.serviceAccountJson,
              ),
          now: now,
        );
      }
      if (ios != null) {
        verifiers[AttestationPlatform.ios] = AppAttestVerifier(
          teamId: ios.teamId,
          bundleId: ios.bundleId,
          environment: ios.environment,
          now: now,
        );
      }
      if (config.allowFake) {
        verifiers[AttestationPlatform.fake] = const FakeAttestationVerifier();
      }
    }
    return AttestationGate(
      mode: config.mode,
      verifiers: verifiers,
      maxPerIpPerMinute: config.maxPerIpPerMinute,
      config: config,
      now: now,
      log: log,
    );
  }

  /// Spenta (com'è nei test che non la riguardano).
  factory AttestationGate.disabled() =>
      AttestationGate(mode: AttestationMode.off);

  /// Quella del processo, dalle variabili d'ambiente.
  static final AttestationGate instance = AttestationGate.fromConfig(
    AttestationConfig.fromEnvironment(),
  );

  final AttestationMode mode;
  final int maxPerIpPerMinute;
  final int maxConcurrentVerifications;
  final Duration verifyTimeout;
  final Duration challengeTtl;

  /// Da dove arriva (per il log d'avvio), se montata dalla configurazione.
  final AttestationConfig? config;
  final SlidingWindowRateLimiter rateLimit;
  final Map<AttestationPlatform, AttestationVerifier> _verifiers;
  final DateTime Function() _now;
  final void Function(String line) _log;
  final Map<AttestationOutcome, int> _counts = {};
  int _inFlight = 0;

  /// `false` con [AttestationMode.off]: nessun challenge.
  bool get isActive => mode != AttestationMode.off;

  /// Le piattaforme verificabili adesso.
  Set<AttestationPlatform> get platforms => _verifiers.keys.toSet();

  /// Quante verifiche per esito da quando il server è partito: le metriche
  /// per decidere il passaggio `log` → `enforce` (vedi la guida).
  Map<AttestationOutcome, int> get counts => Map.unmodifiable(_counts);

  /// Un challenge nuovo per un `hello` che aprirebbe una sessione.
  AttestationChallenge issueChallenge() =>
      AttestationChallenge.issue(now: _now(), ttl: challengeTtl);

  /// Decide sul messaggio `attestation` arrivato per [challenge] (lo
  /// consuma: una seconda chiamata con lo stesso challenge è
  /// [AttestationOutcome.expiredChallenge]). [ip] serve solo al limite per
  /// IP, mai scritto nel log.
  Future<AttestationDecision> evaluate({
    required AttestationChallenge challenge,
    required Map<String, dynamic> message,
    required String ip,
  }) async {
    final evidence = AttestationEvidence.fromMessage(message);
    if (!challenge.consume(_now())) {
      return _decide(AttestationOutcome.expiredChallenge, evidence?.platform);
    }
    if (evidence == null) {
      return _decide(AttestationOutcome.missing, null);
    }
    final verifier = _verifiers[evidence.platform];
    if (verifier == null) {
      return _decide(AttestationOutcome.unsupportedPlatform, evidence.platform);
    }
    if (!rateLimit.tryAcquire(ip)) {
      return _decide(AttestationOutcome.rateLimited, evidence.platform);
    }
    if (_inFlight >= maxConcurrentVerifications) {
      return _decide(
        AttestationOutcome.unavailable,
        evidence.platform,
        'troppe verifiche in corso',
      );
    }

    _inFlight++;
    try {
      await verifier
          .verify(evidence, nonce: challenge.nonce)
          .timeout(verifyTimeout);
      return _decide(AttestationOutcome.valid, evidence.platform);
    } on AttestationRejectedException catch (e) {
      return _decide(
        AttestationOutcome.invalid,
        evidence.platform,
        e.reason.name,
      );
    } on AttestationUnavailableException catch (e) {
      return _decide(
        AttestationOutcome.unavailable,
        evidence.platform,
        e.detail,
      );
    } on TimeoutException {
      return _decide(
        AttestationOutcome.unavailable,
        evidence.platform,
        'timeout della verifica',
      );
    } catch (e) {
      // Un errore inatteso del verificatore non deve mai far passare in
      // enforce né far cadere il socket.
      return _decide(
        AttestationOutcome.unavailable,
        evidence.platform,
        e.runtimeType.toString(),
      );
    } finally {
      _inFlight--;
    }
  }

  /// Il client non ha risposto al challenge in tempo.
  AttestationDecision timedOut() => _decide(AttestationOutcome.timeout, null);

  AttestationDecision _decide(
    AttestationOutcome outcome,
    AttestationPlatform? platform, [
    String detail = '',
  ]) {
    _counts[outcome] = (_counts[outcome] ?? 0) + 1;
    final decision = switch ((mode, outcome)) {
      (_, AttestationOutcome.valid) => AttestationDecision.allow,
      (AttestationMode.enforce, AttestationOutcome.rateLimited) =>
        AttestationDecision.rateLimited,
      (AttestationMode.enforce, _) => AttestationDecision.deny,
      _ => AttestationDecision.allow,
    };
    final totals = [
      for (final entry in _counts.entries) '${entry.key.name} ${entry.value}',
    ].join(', ');
    _log(
      '[attestazione] ${mode.name}: ${platform?.name ?? '-'} '
      '${outcome.name}${detail.isEmpty ? '' : ' ($detail)'} → '
      '${decision.name} — totali: $totals',
    );
    return decision;
  }
}
