import 'dart:io';

/// Contatori **aggregati** del processo, per `GET /metrics`: quanti
/// messaggi di ogni tipo, quanti rifiuti per motivo, gli esiti degli
/// acquisti e dei record di moderazione. Solo in RAM, solo numeri: nessun
/// identificativo, nessun IP, nessun contenuto — le chiavi sono nomi fissi
/// del codice (il tipo di un messaggio del client entra solo se è uno dei
/// tipi noti, vedi [knownMessageTypes]).
class Metrics {
  Metrics._();

  static final Metrics instance = Metrics._();

  /// Solo per i test: un'istanza vuota.
  factory Metrics.forTest() = Metrics._;

  static const knownMessageTypes = {
    'hello',
    'attestation',
    'presence',
    'sendEncounterRequest',
    'respondToEncounterRequest',
    'endMatch',
    'chatMessage',
    'block',
    'report',
    'ping',
    'end',
  };

  final Map<String, int> _messages = {};
  final Map<String, int> _rejected = {};
  final Map<String, int> _purchases = {};
  final Map<String, int> _moderationRecords = {};
  final Map<String, int> _connections = {};
  final DateTime _startedAt = DateTime.now();

  static final _safeKey = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,40}$');

  static String _key(Object? raw, {Set<String>? allowed}) {
    if (raw is! String) return 'other';
    if (allowed != null) return allowed.contains(raw) ? raw : 'other';
    return _safeKey.hasMatch(raw) ? raw : 'other';
  }

  void message(Object? type) =>
      _bump(_messages, _key(type, allowed: knownMessageTypes));

  /// Un `rejected` mandato a un client, per [reason] (lista chiusa del
  /// codice).
  void rejected(String reason) => _bump(_rejected, _key(reason));

  /// Esito di un `POST /paywall/purchase`: `granted`, `replayed`,
  /// `rejected_<motivo>`, `alreadyRedeemed`, `storeUnavailable`…
  void purchase(String outcome) => _bump(_purchases, _key(outcome));

  void moderationRecord({required bool saved}) =>
      _bump(_moderationRecords, saved ? 'saved' : 'failed');

  /// `accepted`, `refusedLimit`, `refusedUpdateRequired`…
  void connection(String outcome) => _bump(_connections, _key(outcome));

  void _bump(Map<String, int> counters, String key) =>
      counters[key] = (counters[key] ?? 0) + 1;

  /// Tutto in un JSON. [gauges] sono i valori "adesso" che il chiamante
  /// legge dagli store (sessioni connesse, in grazia…) e [attestations] i
  /// contatori della verifica del dispositivo.
  Map<String, Object?> snapshot({
    Map<String, int> gauges = const {},
    Map<String, int> attestations = const {},
  }) => {
    'uptimeSeconds': DateTime.now().difference(_startedAt).inSeconds,
    'rssBytes': _rss(),
    'sessions': gauges,
    'connections': Map<String, int>.of(_connections),
    'messages': Map<String, int>.of(_messages),
    'rejected': Map<String, int>.of(_rejected),
    'purchases': Map<String, int>.of(_purchases),
    'attestations': attestations,
    'moderationRecords': Map<String, int>.of(_moderationRecords),
  };

  static int _rss() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }
}
