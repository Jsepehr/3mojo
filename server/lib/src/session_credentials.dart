import 'dart:math';

/// Separa la **credenziale** di una sessione dal suo **id pubblico**.
///
/// Il client si presenta su `/ws` con un segreto che genera lui allo Start
/// (`OnlineSession.sessionId`, un UUID v4) e che non esce mai dal suo
/// telefono e da questo server. Tutto il resto del server — `SessionStore`,
/// `EncounterStore`, `ConnectionHub`, e quindi ogni payload verso gli altri
/// utenti (lista vicinanze, richieste, chat) — usa solo l'id pubblico
/// casuale assegnato qui.
///
/// Prima erano la stessa stringa: chi riceveva l'id di qualcuno nella lista
/// vicinanze poteva aprire `/ws?sessionId=<quell'id>` e prendersi il suo
/// canale (chat, richieste, presenza a suo nome). Ora conoscere un id
/// pubblico non dà accesso a nulla.
///
/// Solo in memoria, come il resto del server: nessuna persistenza.
class SessionCredentials {
  SessionCredentials._({Random? random}) : _random = random ?? Random.secure();

  /// Solo per i test: un'istanza vuota e indipendente.
  factory SessionCredentials.empty({Random? random}) =>
      SessionCredentials._(random: random);

  static final SessionCredentials instance = SessionCredentials._();

  /// Lunghezza minima del segreto: un UUID v4 ne ha 36. Sotto questa
  /// soglia potrebbe essere indovinabile.
  static const minSecretLength = 32;

  final Random _random;
  final Map<String, String> _publicIdBySecret = {};

  static bool isValidSecret(String? secret) =>
      secret != null && secret.length >= minSecretLength;

  /// L'id pubblico legato a [secret]: lo stesso finché la sessione resta
  /// viva (anche dopo una riconnessione), uno nuovo casuale altrimenti.
  String publicIdFor(String secret) =>
      _publicIdBySecret.putIfAbsent(secret, _newPublicId);

  /// Dimentica il legame alla fine della sessione: un nuovo Start con lo
  /// stesso segreto riceverebbe un id pubblico nuovo.
  void forget(String secret) => _publicIdBySecret.remove(secret);

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
