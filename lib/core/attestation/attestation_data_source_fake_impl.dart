import '/core/config/attestation_config.dart';
import 'attestation_data_source.dart';
import 'device_attestation.dart';

/// Attestazione **finta** dei build di debug: nessun Apple, nessun Google.
/// Il token è legato al nonce come quelli veri
/// (`"<AttestationConfig.fakeTokenPrefix><nonce>"`), così in prova anche il
/// riuso o il socket sbagliato vengono rifiutati. Il server la accetta solo
/// con `ATTESTATION_ALLOW_FAKE=true` su un server non pubblico
/// (`FakeAttestationVerifier`).
class AttestationDataSourceFakeImpl implements AttestationDataSource {
  const AttestationDataSourceFakeImpl();

  @override
  Future<DeviceAttestation> attest(String nonce) async =>
      DeviceAttestation.fake('${AttestationConfig.fakeTokenPrefix}$nonce');
}
