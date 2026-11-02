import 'dart:convert';
import 'dart:io';

import 'package:threemojo_server/src/admin_reports_api.dart';
import 'package:threemojo_server/src/moderation_records.dart';

/// `RAEN_ENV` e i controlli "fail closed" dell'avvio.
///
/// Con `RAEN_ENV=production` il server **non parte** se la configurazione
/// lascerebbe aperta una porta pensata per lo sviluppo o ne dimenticherebbe
/// una di sicurezza: meglio un deploy che fallisce subito, e si vede, che un
/// server in produzione che regala sblocchi o non salva le segnalazioni.
/// Senza `RAEN_ENV` (o `development`) valgono i default da sviluppo, con
/// una sola eccezione che vale **sempre**: `PAYMENTS_MODE=fake` esplicito su
/// un server con TLS o `TRUSTED_PROXY` (cioè pubblico) è rifiutato.
class ServerEnvironment {
  const ServerEnvironment._();

  static const variable = 'RAEN_ENV';
  static const dataDirVariable = 'DATA_DIR';
  static const defaultDataDir = 'data';

  static String _value(Map<String, String> env, String name) =>
      env[name]?.trim() ?? '';

  /// `true` solo con `RAEN_ENV=production` (maiuscole ignorate).
  static bool isProduction(Map<String, String> env) =>
      _value(env, variable).toLowerCase() == 'production';

  /// La cartella dello stato persistente (sblocchi, transazioni): `DATA_DIR`
  /// o `data` nella cartella di lavoro.
  static String dataDir(Map<String, String> env) {
    final raw = _value(env, dataDirVariable);
    return raw.isEmpty ? defaultDataDir : raw;
  }

  /// `true` se il server è raggiungibile dall'esterno (TLS diretto o dietro
  /// un proxy fidato).
  static bool looksPublic(Map<String, String> env) =>
      _value(env, 'TLS_CERT_PATH').isNotEmpty ||
      _value(env, 'TRUSTED_PROXY').isNotEmpty;

  static bool _isTrue(Map<String, String> env, String name) {
    final value = _value(env, name).toLowerCase();
    return value.isNotEmpty && value != 'false' && value != '0';
  }

  /// I motivi per cui il server **non deve partire** con questa
  /// configurazione (vuota = si può partire).
  static List<String> fatalProblems(Map<String, String> env) {
    final problems = <String>[];
    final rawEnv = _value(env, variable).toLowerCase();
    if (rawEnv.isNotEmpty &&
        rawEnv != 'production' &&
        rawEnv != 'development') {
      problems.add(
        '$variable="${_value(env, variable)}" non valido: production o '
        'development (un refuso non deve far partire un server "da '
        'sviluppo" in produzione).',
      );
    }

    final paymentsMode = _value(env, 'PAYMENTS_MODE').toLowerCase();
    if (paymentsMode == 'fake' && looksPublic(env)) {
      problems.add(
        'PAYMENTS_MODE=fake su un server con TLS_CERT_PATH o TRUSTED_PROXY: '
        'chiunque potrebbe sbloccare senza pagare. Il finto è solo per '
        'lo sviluppo locale.',
      );
    }

    if (!isProduction(env)) return problems;

    if (paymentsMode != 'real') {
      problems.add('In production serve PAYMENTS_MODE=real.');
    }
    if (_moderationKeyProblem(env) != null) {
      problems.add(
        'In production serve una MODERATION_KEY valida: '
        '${_moderationKeyProblem(env)}',
      );
    }
    final adminToken = _value(env, AdminReportsApi.tokenEnvironmentVariable);
    if (adminToken.length < AdminReportsApi.minTokenLength) {
      problems.add(
        'In production serve ADMIN_TOKEN di almeno '
        '${AdminReportsApi.minTokenLength} caratteri '
        '(openssl rand -hex 32).',
      );
    }
    if (_hashKeyProblem(env) != null) {
      problems.add(
        'In production serve PAYMENTS_TRANSACTION_HASH_KEY fissa '
        '(${_hashKeyProblem(env)}): senza, il registro delle transazioni '
        'non sopravvive a un riavvio.',
      );
    }
    if (_value(env, 'DEBUG_ENDPOINTS_TOKEN').isNotEmpty) {
      problems.add('In production DEBUG_ENDPOINTS_TOKEN non va impostato.');
    }
    if (_isTrue(env, AdminReportsApi.allowInsecureEnvironmentVariable)) {
      problems.add('In production ADMIN_ALLOW_INSECURE_HTTP non va impostato.');
    }
    if (_isTrue(env, 'ATTESTATION_ALLOW_FAKE')) {
      problems.add('In production ATTESTATION_ALLOW_FAKE non va impostato.');
    }
    return problems;
  }

  static String? _moderationKeyProblem(Map<String, String> env) {
    final raw = _value(env, ModerationRecordStore.keyEnvironmentVariable);
    if (raw.isEmpty) return 'manca.';
    try {
      if (base64Decode(raw).length == ModerationRecordStore.keyLength) {
        return null;
      }
    } on FormatException {
      // sotto
    }
    return 'non è di ${ModerationRecordStore.keyLength} byte in base64.';
  }

  static String? _hashKeyProblem(Map<String, String> env) {
    final raw = _value(env, 'PAYMENTS_TRANSACTION_HASH_KEY');
    if (raw.isEmpty) return 'manca';
    try {
      if (base64Decode(raw).length >= 32) return null;
    } on FormatException {
      // sotto
    }
    return 'non è di almeno 32 byte in base64';
  }

  /// Lancia `StateError` con tutti i motivi se il server non deve partire.
  static void requireValid(Map<String, String> env) {
    final problems = fatalProblems(env);
    if (problems.isEmpty) return;
    throw StateError(
      'Configurazione non valida, il server non parte:\n'
      '${problems.map((p) => '- $p').join('\n')}',
    );
  }

  /// Comodo per `main.dart`.
  static Map<String, String> get current => Platform.environment;
}
