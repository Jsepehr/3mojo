/// Chi ha bloccato chi, per **id interni** di sessione — mai pseudonimi:
/// lo pseudonimo è per osservatore, l'id interno è lo stesso per tutta la
/// vita della sessione (anche attraverso la grazia e le riconnessioni, vedi
/// `SessionLifecycle`), quindi il blocco vale finché vive la sessione di
/// chi blocca.
///
/// Il blocco vale **nei due sensi** ([isBlockedEitherWay]): chi blocca non
/// vede più l'altro, e l'altro non vede più chi l'ha bloccato (vedi
/// `SessionStore.nearbyPeople`, `ConnectionHub.relayChatMessage`,
/// `RealtimeMessageHandler`).
///
/// **Non sopravvive alla fine della sessione** ([forgetSession], chiamato da
/// `SessionLifecycle.endNow`): non esistono id permanenti per scelta di
/// prodotto, quindi dopo un End e un nuovo Start (di chi blocca **o** di
/// chi è bloccato, che riceve un id nuovo) i due possono rivedersi. È un
/// limite noto, detto onestamente nel testo di conferma dell'app.
///
/// Solo in RAM, come il resto dello stato di sessione.
class BlockStore {
  BlockStore._();

  /// Solo per i test: un'istanza vuota e indipendente.
  factory BlockStore.empty() => BlockStore._();

  static final BlockStore instance = BlockStore._();

  /// blocker → chi ha bloccato.
  final Map<String, Set<String>> _blockedBy = {};

  /// [blockerId] blocca [blockedId] (id interni). Idempotente; bloccare se
  /// stessi non fa nulla.
  void block(String blockerId, String blockedId) {
    if (blockerId == blockedId) return;
    _blockedBy.putIfAbsent(blockerId, () => {}).add(blockedId);
  }

  /// `true` se una delle due sessioni ha bloccato l'altra.
  bool isBlockedEitherWay(String a, String b) =>
      (_blockedBy[a]?.contains(b) ?? false) ||
      (_blockedBy[b]?.contains(a) ?? false);

  /// Dimentica ogni blocco in cui compare [sessionId], come chi blocca o
  /// come bloccato — alla fine della sessione.
  void forgetSession(String sessionId) {
    _blockedBy.remove(sessionId);
    for (final blocked in _blockedBy.values) {
      blocked.remove(sessionId);
    }
    _blockedBy.removeWhere((_, blocked) => blocked.isEmpty);
  }

  /// Quante sessioni hanno bloccato qualcuno — solo per test e diagnostica.
  int get blockerCount => _blockedBy.length;
}
