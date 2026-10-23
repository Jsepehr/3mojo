import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Le radici di cui ci si fida per le transazioni e le notifiche firmate
/// dall'App Store (JWS con catena `x5c`).
///
/// **Apple Root CA - G3** è incluso qui: è un certificato pubblico,
/// scaricato da <https://www.apple.com/certificateauthority/AppleRootCA-G3.cer>
/// (valido dal 30/04/2014 al 30/04/2039), impronta SHA-256
/// `63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179` —
/// la stessa pubblicata da Apple e controllata nei test
/// (`apple_jws_verifier_test.dart`). Non è un segreto.
///
/// Se Apple dovesse introdurre una nuova radice prima del 2039, la si
/// aggiunge senza toccare il codice con `APPLE_ROOT_CA_PATH` (uno o più
/// file `.cer` DER o PEM, separati da virgola): si sommano a quella inclusa.
class AppleRootCertificates {
  const AppleRootCertificates._();

  static const appleRootCaG3Sha256 =
      '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179';

  static final Uint8List appleRootCaG3 = base64.decode(
    'MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUg'
    'Um9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTET'
    'MBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkw'
    'NDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFw'
    'cGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYD'
    'VQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHc'
    'FBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dv'
    'MVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr'
    'MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD'
    '6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK'
    '1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==',
  );

  /// La radice inclusa più quelle in `APPLE_ROOT_CA_PATH`. Un file
  /// illeggibile fa fallire l'avvio della verifica Apple (lo dice
  /// `PaymentsConfig`), non viene ignorato in silenzio.
  static List<Uint8List> trustedRoots(Map<String, String> environment) {
    final extra = (environment['APPLE_ROOT_CA_PATH'] ?? '')
        .split(',')
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty);
    return [appleRootCaG3, for (final path in extra) _readCertificate(path)];
  }

  static Uint8List _readCertificate(String path) {
    final bytes = File(path).readAsBytesSync();
    final text = latin1.decode(bytes, allowInvalid: true);
    final match = RegExp(
      r'-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\s]+)-----END CERTIFICATE-----',
    ).firstMatch(text);
    if (match == null) return bytes;
    return base64.decode(match.group(1)!.replaceAll(RegExp(r'\s'), ''));
  }
}
