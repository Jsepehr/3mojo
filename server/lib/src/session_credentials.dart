import 'dart:math';

/// Separa la **credenziale** di una sessione dal suo **id pubblico**.
///
/// Il client si presenta su `/ws` con un segreto che genera lui allo Start
/// (`OnlineSession.sessionId`, un UUID v4) e che non esce mai dal suo
/// telefono e da questo server — mandato nel primo messaggio del socket
/// (`{"type": "hello", "secret": ...}`), **mai nell'URL**: gli URL finiscono
/// per default nei log di proxy, load balancer e provider. Tutto il resto del server — `SessionStore`,
/// `EncounterStore`, `ConnectionHub`, e quindi ogni payload verso gli altri
/// utenti (lista vicinanze, richieste, chat) — usa solo l'id pubblico
/// casuale assegnato qui.
///
/// Prima erano la stessa stringa: chi riceveva l'id di qualcuno nella lista
/// vicinanze poteva presentarsi con quell'id e prendersi il suo canale
/// (chat, richieste, presenza a suo nome). Ora l'id interno non esce
/// nemmeno più dal server: agli altri client arrivano solo pseudonimi per
/// osservatore (vedi `Pseudonyms`).
///
/// Solo in memoria, come tutto lo stato di sessione: nessuna persistenza
/// (i record di moderazione, `ModerationRecordStore`, non contengono né
/// segreti né id).
class SessionCredentials {
  SessionCredentials._({Random? random}) : _random = random ?? Random.secure();

  /// Solo per i test: un'istanza vuota e indipendente.
  factory SessionCredentials.empty({Random? random}) =>
      SessionCredentials._(random: random);

  static final SessionCredentials instance = SessionCredentials._();

  /// Lunghezza minima del segreto: un UUID v4 ne ha 36. Sotto questa
  /// soglia potrebbe essere indovinabile.
  static const minSecretLength = 32;

  /// Oltre questa lunghezza non è un segreto generato dall'app.
  static const maxSecretLength = 128;

  final Random _random;
  final Map<String, String> _publicIdBySecret = {};
  final Map<String, String> _secretByPublicId = {};

  static bool isValidSecret(String? secret) =>
      secret != null &&
      secret.length >= minSecretLength &&
      secret.length <= maxSecretLength;

  /// `true` se [secret] appartiene a una sessione ancora viva (quindi una
  /// connessione con questo segreto è una riconnessione, non un nuovo Start).
  bool knows(String secret) => _publicIdBySecret.containsKey(secret);

  /// L'id pubblico legato a [secret]: lo stesso finché la sessione resta
  /// viva (anche dopo una riconnessione), uno nuovo casuale altrimenti.
  String publicIdFor(String secret) {
    final existing = _publicIdBySecret[secret];
    if (existing != null) return existing;
    var publicId = _newPublicId();
    while (_secretByPublicId.containsKey(publicId)) {
      publicId = _newPublicId();
    }
    _publicIdBySecret[secret] = publicId;
    _secretByPublicId[publicId] = secret;
    return publicId;
  }

  /// Dimentica il legame alla fine della sessione: un nuovo Start con lo
  /// stesso segreto riceverebbe un id pubblico nuovo.
  void forget(String secret) {
    final publicId = _publicIdBySecret.remove(secret);
    if (publicId != null) _secretByPublicId.remove(publicId);
  }

  /// Come [forget], partendo dall'id pubblico — è quello che conosce chi
  /// chiude la sessione (`SessionLifecycle.endNow`).
  void forgetPublicId(String publicId) {
    final secret = _secretByPublicId.remove(publicId);
    if (secret != null) _publicIdBySecret.remove(secret);
  }

  /// 128 bit casuali in esadecimale: non derivati dal segreto, quindi
  /// dall'id pubblico non si risale in alcun modo alla credenziale.
  String _newPublicId() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
