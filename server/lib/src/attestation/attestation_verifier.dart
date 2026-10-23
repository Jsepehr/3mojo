import 'dart:convert';
import 'dart:typed_data';

/// Da quale piattaforma dichiara di arrivare un'attestazione (`platform`
/// nel messaggio `attestation`). È solo una dichiarazione del client: decide
/// **quale** verificatore la controlla, mai se controllarla.
enum AttestationPlatform {
  /// Play Integrity (Standard API), vedi `PlayIntegrityVerifier`.
  android,

  /// App Attest, vedi `AppAttestVerifier`.
  ios,

  /// Attestazione **finta** dei build di debug (`FakeAttestationVerifier`):
  /// accettata solo con `ATTESTATION_ALLOW_FAKE=true` su un server non
  /// pubblico.
  fake;

  static AttestationPlatform? fromName(Object? name) {
    for (final platform in values) {
      if (platform.name == name) return platform;
    }
    return null;
  }
}

/// Ciò che il client ha mandato nel messaggio `attestation` (vedi
/// `server/routes/ws.dart`), già controllato nella forma ma **non**
/// verificato. Vive solo durante la verifica: non viene mai salvato né
/// scritto nel log.
sealed class AttestationEvidence {
  const AttestationEvidence();

  AttestationPlatform get platform;

  /// Lunghezza massima di ogni campo (un token Play Integrity è qualche
  /// KB, un attestation object App Attest ~6 KB, ~8 KB in base64).
  static const maxFieldLength = 16 * 1024;

  /// Dal messaggio `attestation`: `null` se il client non ha un'attestazione
  /// (nessuna `platform`: sul telefono non è riuscita) o se la forma è
  /// sbagliata — per la regola delle modalità le due cose contano uguale,
  /// "nessuna attestazione valida".
  static AttestationEvidence? fromMessage(Map<String, dynamic> message) {
    final platform = AttestationPlatform.fromName(message['platform']);
    String? field(String name) {
      final value = message[name];
      if (value is! String || value.isEmpty) return null;
      if (value.length > maxFieldLength) return null;
      return value;
    }

    switch (platform) {
      case null:
        return null;
      case AttestationPlatform.android:
        final token = field('token');
        return token == null ? null : PlayIntegrityEvidence(token);
      case AttestationPlatform.fake:
        final token = field('token');
        return token == null ? null : FakeAttestationEvidence(token);
      case AttestationPlatform.ios:
        final keyId = _decodeBase64(field('keyId'));
        final object = _decodeBase64(field('attestationObject'));
        if (keyId == null || object == null) return null;
        return AppAttestEvidence(keyId: keyId, attestationObject: object);
    }
  }

  /// Base64 standard o URL-safe, con o senza `=` finali.
  static Uint8List? _decodeBase64(String? value) {
    if (value == null) return null;
    try {
      final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
      return base64.decode(base64.normalize(normalized));
    } on FormatException {
      return null;
    }
  }
}

/// Un token della Play Integrity API (Standard), da far decodificare a
/// Google.
class PlayIntegrityEvidence extends AttestationEvidence {
  const PlayIntegrityEvidence(this.token);

  final String token;

  @override
  AttestationPlatform get platform => AttestationPlatform.android;
}

/// Una chiave App Attest appena generata ([keyId] = SHA-256 della sua
/// chiave pubblica) e la sua attestazione (CBOR) firmata da Apple.
class AppAttestEvidence extends AttestationEvidence {
  const AppAttestEvidence({
    required this.keyId,
    required this.attestationObject,
  });

  final Uint8List keyId;
  final Uint8List attestationObject;

  @override
  AttestationPlatform get platform => AttestationPlatform.ios;
}

/// L'attestazione finta dei build di debug.
class FakeAttestationEvidence extends AttestationEvidence {
  const FakeAttestationEvidence(this.token);

  final String token;

  @override
  AttestationPlatform get platform => AttestationPlatform.fake;
}

/// Perché un'attestazione non è valida (solo per il log e i test: al
/// client arriva sempre e solo `attestationRequired`).
enum AttestationRejection {
  /// Forma sbagliata: token illeggibile, CBOR rotto, campi mancanti.
  malformed,

  /// Non è legata al challenge di questo socket.
  wrongNonce,

  /// Non è la nostra app (pacchetto, Team ID + bundle id).
  wrongApp,

  /// L'app non è quella pubblicata (Play: non `PLAY_RECOGNIZED`).
  unrecognizedApp,

  /// Il dispositivo non è integro (Play: niente `MEETS_DEVICE_INTEGRITY`).
  deviceNotTrusted,

  /// Catena di certificati non fidata o scaduta (App Attest).
  untrustedCertificate,

  /// Il verdetto è troppo vecchio (o "dal futuro").
  stale,

  /// Una chiave App Attest già usata (contatore diverso da 0) o di un
  /// ambiente (development/production) diverso da quello configurato.
  wrongKeyState,
}

/// L'attestazione è stata controllata ed è **non valida**.
class AttestationRejectedException implements Exception {
  const AttestationRejectedException(this.reason, [this.detail = '']);

  final AttestationRejection reason;

  /// Dettaglio tecnico per il log (mai dati del dispositivo).
  final String detail;

  @override
  String toString() =>
      'AttestationRejectedException(${reason.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// La verifica **non si è potuta fare** (Google non risponde, credenziali
/// del service account rifiutate): non si sa se l'attestazione è valida.
class AttestationUnavailableException implements Exception {
  const AttestationUnavailableException(this.detail);

  final String detail;

  @override
  String toString() => 'AttestationUnavailableException($detail)';
}

/// Verifica un'attestazione di una piattaforma contro il nonce del
/// challenge di questo socket. Esito: completa normalmente (valida),
/// [AttestationRejectedException] (non valida) o
/// [AttestationUnavailableException] (non verificabile ora).
///
/// **Nessuno stato**: un verificatore non ricorda nulla delle attestazioni
/// che ha visto (niente keyId, niente token, niente verdetti).
abstract class AttestationVerifier {
  AttestationPlatform get platform;

  Future<void> verify(AttestationEvidence evidence, {required String nonce});
}
