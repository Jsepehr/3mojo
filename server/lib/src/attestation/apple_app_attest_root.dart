import 'dart:convert';
import 'dart:typed_data';

/// La radice di cui ci si fida per le attestazioni **App Attest**.
///
/// **Apple App Attestation Root CA** è inclusa qui: è un certificato
/// pubblico, scaricato da
/// <https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem>
/// (valido dal 18/03/2020 al 15/03/2045, chiave P-384, autofirmato),
/// impronta SHA-256 del certificato DER
/// `1cb9823ba28ba6ad2d33a006941de2ae4f513ef1d4e831b9f7e0fa7b6242c932`.
/// Apple non pubblica l'impronta: è stata calcolata sul file scaricato via
/// HTTPS da apple.com (`openssl x509 -outform der | shasum -a 256`), la sua
/// autofirma è valida, e l'intermedio "Apple App Attestation CA 1"
/// dell'attestazione d'esempio pubblicata da Apple nell'"Attestation Object
/// Validation Guide" è firmato da lei. I test lo controllano
/// (`app_attest_verifier_test.dart`). Non è un segreto.
///
/// È una radice **diversa** da Apple Root CA - G3 dei pagamenti
/// (`payments/apple_root_certificates.dart`): App Attest ha una PKI sua.
class AppleAppAttestRoot {
  const AppleAppAttestRoot._();

  static const sha256Fingerprint =
      '1cb9823ba28ba6ad2d33a006941de2ae4f513ef1d4e831b9f7e0fa7b6242c932';

  static final Uint8List certificate = base64.decode(
    'MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYwJAYDVQQD'
    'DB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwKQXBwbGUgSW5jLjET'
    'MBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNaFw00NTAzMTUwMDAwMDBaMFIx'
    'JjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlvbiBSb290IENBMRMwEQYDVQQKDApBcHBs'
    'ZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9ybmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHh'
    'mLW07ATaFQIEVwTtT4dyctdhNbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/'
    'cLiP1sOUtgjqK9auYen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8E'
    'BTADAQH/MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw'
    'CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn53O5+FRX'
    'geLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijVoyFraWVIyd/dganm'
    'rduC1bmTBGwD',
  );
}
