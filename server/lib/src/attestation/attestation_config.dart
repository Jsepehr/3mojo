import 'dart:convert';
import 'dart:io';

import 'app_attest_verifier.dart';

/// Che cosa fa il server con la verifica del dispositivo
/// (`ATTESTATION_MODE`).
enum AttestationMode {
  /// **Default.** Nessun challenge, nessuna verifica: il protocollo è
  /// identico a prima (`hello` → `welcome`).
  off,

  /// Challenge e verifica a ogni sessione nuova, esito **solo nel log**:
  /// nessuno viene rifiutato. Serve a misurare quante sessioni passerebbero
  /// prima di accendere [enforce].
  log,

  /// Senza un'attestazione valida una sessione nuova non nasce: `error`
  /// `attestationRequired` e chiusura (4011).
  enforce,
}

/// Configurazione Play Integrity (Android).
class PlayIntegritySettings {
  const PlayIntegritySettings({
    required this.packageName,
    required this.serviceAccountJson,
  });

  final String packageName;

  /// Il contenuto del JSON del service account (mai loggato).
  final String serviceAccountJson;
}

/// Configurazione App Attest (iOS).
class AppAttestSettings {
  const AppAttestSettings({
    required this.teamId,
    required this.bundleId,
    required this.environment,
  });

  final String teamId;
  final String bundleId;
  final AppAttestEnvironment environment;
}

/// Tutta la configurazione della verifica del dispositivo, letta dalle
/// variabili d'ambiente all'avvio (tabella in `server/README.md`).
///
/// **Configurazione incompleta con `enforce`**: il server **non parte**
/// ([fatalProblem], vedi `main.dart`) — invece di rifiutare in silenzio
/// tutti gli utenti di una piattaforma non configurata, o di lasciarli
/// passare senza verifica (la piattaforma la dichiara il client: una
/// piattaforma "aperta" sarebbe la porta per tutti gli script). Lo stesso
/// per un `ATTESTATION_MODE` scritto male. Con `log` una piattaforma non
/// configurata finisce solo nel log (`unsupportedPlatform`).
///
/// Eccezione solo per lo sviluppo: con l'attestazione finta accesa
/// ([allowFake]) `enforce` parte anche senza Apple/Google, e le
/// piattaforme vere non configurate vengono rifiutate.
class AttestationConfig {
  const AttestationConfig({
    required this.mode,
    this.playIntegrity,
    this.appAttest,
    this.allowFake = false,
    this.maxPerIpPerMinute = defaultMaxPerIpPerMinute,
    this.problems = const [],
    this.fatalProblem,
  });

  /// Spenta: com'è senza variabili d'ambiente.
  static const disabled = AttestationConfig(mode: AttestationMode.off);

  /// Oltre questo numero di attestazioni al minuto dallo stesso IP non si
  /// verifica più (ognuna costa una chiamata a Google, e una quota
  /// giornaliera): `rateLimited`. Alto quanto basta per un Wi-Fi condiviso.
  static const defaultMaxPerIpPerMinute = 10;

  factory AttestationConfig.fromEnvironment([
    Map<String, String>? environment,
  ]) {
    final env = environment ?? Platform.environment;
    final problems = <String>[];

    // TODO(attestation): in produzione, quando le credenziali sotto
    // esistono, `ATTESTATION_MODE=log` e poi `enforce` (metriche e passi
    // nella guida, "Per attivare la verifica del dispositivo").
    final rawMode = (_value(env, 'ATTESTATION_MODE') ?? 'off').toLowerCase();
    final mode = switch (rawMode) {
      'off' => AttestationMode.off,
      'log' => AttestationMode.log,
      'enforce' => AttestationMode.enforce,
      _ => null,
    };
    if (mode == null) {
      return AttestationConfig(
        mode: AttestationMode.off,
        fatalProblem:
            'ATTESTATION_MODE="$rawMode" non valido (off|log|enforce): il '
            'server non parte, invece di indovinare.',
      );
    }
    if (mode == AttestationMode.off) return disabled;

    final looksPublic =
        _value(env, 'TLS_CERT_PATH') != null ||
        _value(env, 'TRUSTED_PROXY') != null;
    var allowFake =
        _value(env, 'ATTESTATION_ALLOW_FAKE')?.toLowerCase() == 'true';
    if (allowFake && looksPublic) {
      allowFake = false;
      problems.add(
        'ATTESTATION_ALLOW_FAKE ignorato: il server sembra pubblico (TLS o '
        'TRUSTED_PROXY), e lì un\'attestazione finta la fabbrica chiunque.',
      );
    } else if (allowFake) {
      problems.add(
        'ATTESTATION_ALLOW_FAKE=true: accettate le attestazioni finte dei '
        'build di debug. Mai in produzione.',
      );
    }

    final playIntegrity = _playIntegrity(env, problems);
    final appAttest = _appAttest(env, problems);

    final rawLimit = int.tryParse(
      _value(env, 'ATTESTATION_MAX_PER_IP_PER_MINUTE') ?? '',
    );
    final limit = rawLimit != null && rawLimit > 0
        ? rawLimit
        : defaultMaxPerIpPerMinute;

    String? fatal;
    if (mode == AttestationMode.enforce &&
        !allowFake &&
        (playIntegrity == null || appAttest == null)) {
      fatal =
          'ATTESTATION_MODE=enforce con la configurazione incompleta '
          '(${[if (playIntegrity == null) 'Android', if (appAttest == null) 'iOS'].join(' e ')} '
          'spento): il server non parte. Completare le variabili o usare '
          'ATTESTATION_MODE=log.';
    }

    return AttestationConfig(
      mode: mode,
      playIntegrity: playIntegrity,
      appAttest: appAttest,
      allowFake: allowFake,
      maxPerIpPerMinute: limit,
      problems: problems,
      fatalProblem: fatal,
    );
  }

  final AttestationMode mode;

  /// `null` = Android non verificabile (configurazione incompleta).
  final PlayIntegritySettings? playIntegrity;

  /// `null` = iOS non verificabile.
  final AppAttestSettings? appAttest;
  final bool allowFake;
  final int maxPerIpPerMinute;
  final List<String> problems;

  /// Se non `null` il server non deve partire (`main.dart`).
  final String? fatalProblem;

  static PlayIntegritySettings? _playIntegrity(
    Map<String, String> env,
    List<String> problems,
  ) {
    // TODO(attestation): servono la Play Integrity API abilitata nel
    // progetto Google Cloud collegato all'app in Play Console e un service
    // account di quel progetto (account Google non ancora esistenti).
    final packageName = _value(env, 'GOOGLE_PACKAGE_NAME');
    // Un service account dedicato, se c'è; altrimenti quello dei pagamenti.
    final accountPath =
        _value(env, 'PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_PATH') ??
        _value(env, 'GOOGLE_SERVICE_ACCOUNT_JSON_PATH');
    if (packageName == null || accountPath == null) {
      problems.add(
        'Verifica Android spenta: servono GOOGLE_PACKAGE_NAME e '
        'PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_PATH (o '
        'GOOGLE_SERVICE_ACCOUNT_JSON_PATH).',
      );
      return null;
    }
    try {
      final json = File(accountPath).readAsStringSync();
      final decoded = jsonDecode(json);
      if (decoded is! Map || decoded['type'] != 'service_account') {
        throw const FormatException('non è un service account');
      }
      return PlayIntegritySettings(
        packageName: packageName,
        serviceAccountJson: json,
      );
    } catch (_) {
      problems.add(
        'Verifica Android spenta: il file del service account è illeggibile '
        'o non è il JSON di un service account.',
      );
      return null;
    }
  }

  static AppAttestSettings? _appAttest(
    Map<String, String> env,
    List<String> problems,
  ) {
    // TODO(attestation): Team ID dell'Apple Developer Program (non ancora
    // esistente) e capability App Attest sull'App ID.
    final teamId = _value(env, 'APPLE_TEAM_ID');
    final bundleId = _value(env, 'APPLE_BUNDLE_ID');
    final environment = AppAttestEnvironment.fromName(
      _value(env, 'APPLE_APP_ATTEST_ENVIRONMENT')?.toLowerCase(),
    );
    if (teamId == null || bundleId == null || environment == null) {
      problems.add(
        'Verifica iOS spenta: servono APPLE_TEAM_ID, APPLE_BUNDLE_ID e '
        'APPLE_APP_ATTEST_ENVIRONMENT (development|production).',
      );
      return null;
    }
    if (!RegExp(r'^[A-Z0-9]{10}$').hasMatch(teamId)) {
      problems.add(
        'Verifica iOS spenta: APPLE_TEAM_ID deve essere di 10 caratteri '
        '(lettere maiuscole e cifre, Membership details nel Developer '
        'portal).',
      );
      return null;
    }
    return AppAttestSettings(
      teamId: teamId,
      bundleId: bundleId,
      environment: environment,
    );
  }

  static String? _value(Map<String, String> env, String name) {
    final value = env[name]?.trim() ?? '';
    return value.isEmpty ? null : value;
  }
}
