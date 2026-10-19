import 'dart:math';

/// Id **per osservatore**: la stessa persona compare con un id diverso a
/// ognuno di quelli che la vedono.
///
/// Prima l'id pubblico di una sessione era lo stesso per tutti: due persone
/// (o due telefoni dello stesso malintenzionato in punti diversi) potevano
/// confrontare le proprie liste e riconoscere con certezza la stessa persona
/// — il primo passo per seguirla o triangolarla. Ora l'id che un client
/// riceve per un'altra persona ha senso solo per quel client.
///
/// Gli pseudonimi sono casuali (non derivati dagli id interni), stabili per
/// tutta la vita della coppia (anche dopo una riconnessione entro la
/// grazia: l'id interno non cambia) e dimenticati quando una delle due
/// sessioni finisce. La mappa inversa traduce gli id che il client rimanda
/// (richieste, chat): un id ricevuto da un altro client non si risolve.
///
/// Solo in memoria, come il resto del server.
class Pseudonyms {
  Pseudonyms({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  /// viewer → (target → pseudonimo)
  final Map<String, Map<String, String>> _forward = {};

  /// viewer → (pseudonimo → target)
  final Map<String, Map<String, String>> _inverse = {};

  /// Lo pseudonimo con cui [viewerId] vede [targetId] (creato al primo
  /// uso).
  String idFor({required String viewerId, required String targetId}) {
    final forViewer = _forward.putIfAbsent(viewerId, () => {});
    final existing = forViewer[targetId];
    if (existing != null) return existing;

    final inverse = _inverse.putIfAbsent(viewerId, () => {});
    var pseudonym = _newId();
    while (inverse.containsKey(pseudonym)) {
      pseudonym = _newId();
    }
    forViewer[targetId] = pseudonym;
    inverse[pseudonym] = targetId;
    return pseudonym;
  }

  /// L'id interno dietro [pseudonym], **solo** se è uno pseudonimo che
  /// [viewerId] ha ricevuto. `null` altrimenti.
  String? resolve({required String viewerId, required String pseudonym}) =>
      _inverse[viewerId]?[pseudonym];

  /// Dimentica ogni pseudonimo in cui compare [sessionId], come osservatore
  /// o come osservato — alla fine della sessione.
  void forget(String sessionId) {
    _forward.remove(sessionId);
    _inverse.remove(sessionId);
    for (final entry in _forward.entries) {
      final pseudonym = entry.value.remove(sessionId);
      if (pseudonym != null) _inverse[entry.key]?.remove(pseudonym);
    }
  }

  String _newId() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
