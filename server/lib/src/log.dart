import 'dart:convert';
import 'dart:io';

enum LogLevel { debug, info, warn, error }

/// Il logger unico del server: **una riga JSON per evento su stderr**
/// (`{"t": ..., "level": ..., "event": ..., ...}`), pronta per `docker logs`
/// o un raccoglitore di log.
///
/// **Cosa non entra mai**: IP, posizione, pseudonimi, segreti di sessione,
/// token, ricevute, selfie. Non si fida di chi chiama:
/// - i campi sono solo numeri, booleani e stringhe **brevi** (le più lunghe
///   di [maxFieldLength] sono tagliate);
/// - ogni stringa passa da [scrub], che cancella ciò che somiglia a un
///   indirizzo IP o a un token (esadecimale/base64 lungo);
/// - di un errore si scrive il **tipo**, mai il messaggio (quello di
///   `FormatException` contiene il testo che non si è riusciti a leggere,
///   cioè dati del client), più poche righe di stack (solo nomi di file).
///
/// I nomi degli eventi sono costanti nel codice (`payments.rejected`,
/// `moderation.save_failed`…), mai costruiti da dati del client.
class Log {
  const Log._();

  /// Dove va la riga. Sostituibile nei test.
  static void Function(String line) sink = stderr.writeln;

  /// Sotto questo livello non si scrive nulla (`LOG_LEVEL`, default `info`).
  static LogLevel minimumLevel = levelFromEnvironment(Platform.environment);

  static DateTime Function() clock = DateTime.now;

  static const maxFieldLength = 200;
  static const maxStackFrames = 5;

  static LogLevel levelFromEnvironment(Map<String, String> environment) {
    final raw = (environment['LOG_LEVEL'] ?? '').trim().toLowerCase();
    for (final level in LogLevel.values) {
      if (level.name == raw) return level;
    }
    return LogLevel.info;
  }

  static void debug(String event, [Map<String, Object?> fields = const {}]) =>
      _write(LogLevel.debug, event, fields);

  static void info(String event, [Map<String, Object?> fields = const {}]) =>
      _write(LogLevel.info, event, fields);

  static void warn(String event, [Map<String, Object?> fields = const {}]) =>
      _write(LogLevel.warn, event, fields);

  /// Un errore: [error] è ridotto al suo tipo (vedi la doc della classe).
  static void error(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => _write(LogLevel.error, event, {
    ...fields,
    if (error != null) 'errorType': error.runtimeType.toString(),
  }, stackTrace: stackTrace);

  static void _write(
    LogLevel level,
    String event,
    Map<String, Object?> fields, {
    StackTrace? stackTrace,
  }) {
    if (level.index < minimumLevel.index) return;
    final line = <String, Object?>{
      't': clock().toUtc().toIso8601String(),
      'level': level.name,
      'event': scrub(event),
      for (final entry in fields.entries) entry.key: _safe(entry.value),
      if (stackTrace != null) 'stack': _frames(stackTrace),
    };
    try {
      sink(jsonEncode(line));
    } catch (_) {
      // Il log non deve mai far cadere il server.
    }
  }

  static Object? _safe(Object? value) => switch (value) {
    null || bool() || num() => value,
    String() => scrub(value),
    Enum() => value.name,
    _ => scrub(value.toString()),
  };

  static List<String> _frames(StackTrace stackTrace) => [
    for (final frame
        in stackTrace.toString().split('\n').where((l) => l.trim().isNotEmpty))
      scrub(frame.trim()),
  ].take(maxStackFrames).toList();

  static final _ipv4 = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');
  static final _ipv6 = RegExp(
    r'\b(?:[0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}\b',
  );
  static final _longToken = RegExp(r'[A-Za-z0-9+/_=-]{24,}');

  /// Toglie da [text] ciò che somiglia a un IP o a un token, e lo accorcia.
  static String scrub(String text) {
    var result = text
        .replaceAll(_ipv4, '[ip]')
        .replaceAll(_ipv6, '[ip]')
        .replaceAll(_longToken, '[redacted]');
    if (result.length > maxFieldLength) {
      result = '${result.substring(0, maxFieldLength)}…';
    }
    return result;
  }
}
