import 'attestation_verifier.dart';

/// Verificatore dell'attestazione **finta** dei build di debug
/// (`AttestationDataSourceFakeImpl` nell'app): nessun Apple, nessun
/// Google, chiunque la può fabbricare. Serve solo a provare in locale il
/// giro completo (challenge → attestazione → `welcome` o
/// `attestationRequired`) con le modalità `log`/`enforce`.
///
/// Acceso solo con `ATTESTATION_ALLOW_FAKE=true` e mai su un server che
/// sembra pubblico (TLS o `TRUSTED_PROXY`, vedi `AttestationConfig`).
///
/// Il token è `"$tokenPrefix<nonce>"`: legato al challenge come quelli
/// veri, così anche in prova un'attestazione di un altro socket (o
/// riusata) viene rifiutata.
class FakeAttestationVerifier implements AttestationVerifier {
  const FakeAttestationVerifier();

  /// Lo stesso prefisso di `AttestationConfig.fakeTokenPrefix` nell'app.
  /// Non è un segreto.
  static const tokenPrefix = 'raen-fake-attestation:';

  static String tokenFor(String nonce) => '$tokenPrefix$nonce';

  @override
  AttestationPlatform get platform => AttestationPlatform.fake;

  @override
  Future<void> verify(
    AttestationEvidence evidence, {
    required String nonce,
  }) async {
    if (evidence is! FakeAttestationEvidence) {
      throw const AttestationRejectedException(AttestationRejection.malformed);
    }
    if (!evidence.token.startsWith(tokenPrefix)) {
      throw const AttestationRejectedException(AttestationRejection.malformed);
    }
    if (evidence.token != tokenFor(nonce)) {
      throw const AttestationRejectedException(AttestationRejection.wrongNonce);
    }
  }
}
