import 'dart:convert';
import 'dart:typed_data';

import '../crypto/ecdsa.dart';
import '../crypto/x509_certificate.dart';
import 'apple_root_certificates.dart';
import 'receipt_verifier.dart';

/// Verifica un **JWS firmato dall'App Store** — una transazione
/// (`signedTransactionInfo`, il `jwsRepresentation` di StoreKit 2) o una
/// notifica server-to-server (`signedPayload`) — e ne ritorna il contenuto.
///
/// Gli stessi controlli della libreria ufficiale di Apple
/// (`app-store-server-library`, `SignedDataVerifier`):
/// 1. intestazione `alg: ES256` con catena `x5c` di **tre** certificati
///    (foglia, intermedio, radice);
/// 2. la radice è **byte per byte** una di quelle fidate
///    ([AppleRootCertificates], Apple Root CA - G3 inclusa);
/// 3. intermedio firmato dalla radice, foglia firmata dall'intermedio,
///    entrambi CA tranne la foglia, tutti validi adesso;
/// 4. foglia con l'OID Apple `1.2.840.113635.100.6.11.1` e intermedio con
///    `1.2.840.113635.100.6.2.1` (certificati emessi apposta per firmare
///    dati dell'App Store, non un qualunque certificato Apple);
/// 5. firma ES256 della foglia su `intestazione.contenuto`.
///
/// Non fa controlli di revoca online (OCSP) dei certificati: come la
/// libreria di Apple con `enableOnlineChecks: false`. TODO(produzione):
/// valutare OCSP se Apple lo richiedesse.
class AppleJwsVerifier {
  AppleJwsVerifier({List<Uint8List>? trustedRoots, DateTime Function()? now})
    : _trustedRoots = trustedRoots ?? [AppleRootCertificates.appleRootCaG3],
      _now = now ?? DateTime.now;

  static const leafMarkerOid = '1.2.840.113635.100.6.11.1';
  static const intermediateMarkerOid = '1.2.840.113635.100.6.2.1';

  final List<Uint8List> _trustedRoots;
  final DateTime Function() _now;

  /// `true` se [value] ha la forma di un JWS compatto (tre parti base64url).
  static bool looksLikeJws(String value) => RegExp(
    r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
  ).hasMatch(value);

  /// Il contenuto del JWS, se la firma e la catena sono valide; altrimenti
  /// [ReceiptRejectedException] con [ReceiptRejection.invalidReceipt].
  Map<String, dynamic> verify(String jws) {
    try {
      return _verify(jws);
    } on ReceiptRejectedException {
      rethrow;
    } on FormatException catch (e) {
      throw ReceiptRejectedException(ReceiptRejection.invalidReceipt, '$e');
    }
  }

  Map<String, dynamic> _verify(String jws) {
    if (!looksLikeJws(jws)) _reject('non è un JWS compatto');
    final parts = jws.split('.');
    final header = _decodeJsonObject(parts[0]);
    if (header['alg'] != 'ES256') _reject('alg diverso da ES256');
    final x5c = header['x5c'];
    if (x5c is! List || x5c.length != 3 || x5c.any((c) => c is! String)) {
      _reject('catena x5c assente o non di tre certificati');
    }
    final chain = [
      for (final encoded in x5c.cast<String>())
        X509Certificate.parse(base64.decode(encoded)),
    ];
    final [leaf, intermediate, root] = chain;

    if (!_trustedRoots.any((trusted) => _sameBytes(trusted, root.der))) {
      _reject('radice non fidata');
    }
    final now = _now().toUtc();
    for (final certificate in chain) {
      if (!certificate.isValidAt(now)) _reject('certificato scaduto');
    }
    if (!intermediate.isSignedBy(root)) _reject('intermedio non firmato');
    if (!leaf.isSignedBy(intermediate)) _reject('foglia non firmata');
    if (leaf.isCertificateAuthority) _reject('la foglia è una CA');
    if (!leaf.extensionOids.contains(leafMarkerOid) ||
        !intermediate.extensionOids.contains(intermediateMarkerOid)) {
      _reject('certificati non emessi per l\'App Store');
    }

    final leafKey = leaf.publicKey;
    if (leafKey == null || leafKey.curve != EcCurve.p256) {
      _reject('chiave della foglia non P-256');
    }
    final signed = Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}'));
    final signature = _decodeBase64Url(parts[2]);
    if (!leafKey.verifyJose(signed, signature, EcdsaHash.sha256)) {
      _reject('firma non valida');
    }
    return _decodeJsonObject(parts[1]);
  }

  static Never _reject(String detail) =>
      throw ReceiptRejectedException(ReceiptRejection.invalidReceipt, detail);

  static Map<String, dynamic> _decodeJsonObject(String part) {
    final Object? value;
    try {
      value = jsonDecode(utf8.decode(_decodeBase64Url(part)));
    } on FormatException {
      _reject('JSON non valido');
    }
    if (value is! Map<String, dynamic>) _reject('JSON non è un oggetto');
    return value;
  }

  static Uint8List _decodeBase64Url(String part) =>
      base64Url.decode(base64Url.normalize(part));
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
