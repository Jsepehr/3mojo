import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:threemojo_server/src/payments/apple_jws_verifier.dart';
import 'package:threemojo_server/src/payments/apple_root_certificates.dart';
import 'package:threemojo_server/src/crypto/der.dart';
import 'package:threemojo_server/src/crypto/ecdsa.dart';
import 'package:threemojo_server/src/payments/receipt_verifier.dart';
import 'package:threemojo_server/src/crypto/x509_certificate.dart';

import 'test_pki.dart';

Matcher _rejected(ReceiptRejection reason) => throwsA(
  isA<ReceiptRejectedException>().having((e) => e.reason, 'reason', reason),
);

void main() {
  group('Apple Root CA - G3 (included)', () {
    test('is the certificate Apple publishes (SHA-256 fingerprint)', () {
      final root = X509Certificate.parse(AppleRootCertificates.appleRootCaG3);

      expect(root.sha256Fingerprint, AppleRootCertificates.appleRootCaG3Sha256);
      expect(root.isCertificateAuthority, isTrue);
      expect(root.publicKey?.curve, EcCurve.p384);
      expect(root.notAfter, DateTime.utc(2039, 4, 30, 18, 19, 6));
    });

    test('verifies its own P-384/SHA-384 signature: the real Apple '
        'certificate exercises the same code path as the chain', () {
      final root = X509Certificate.parse(AppleRootCertificates.appleRootCaG3);

      expect(root.isSignedBy(root), isTrue);
    });

    test('a single flipped bit in the signed part breaks the signature', () {
      final bytes = Uint8List.fromList(AppleRootCertificates.appleRootCaG3);
      bytes[200] ^= 0x01;
      final tampered = X509Certificate.parse(bytes);
      final root = X509Certificate.parse(AppleRootCertificates.appleRootCaG3);

      expect(tampered.isSignedBy(root), isFalse);
    });
  });

  group('DER', () {
    test('malformed input is a FormatException, never a range error', () {
      for (final bytes in [
        <int>[],
        [0x30],
        [0x30, 0x05, 0x01],
        [0x30, 0x80, 0x00, 0x00],
        [0x1f, 0x01, 0x00],
        [0x30, 0x85, 1, 1, 1, 1, 1],
      ]) {
        expect(
          () => DerNode.parse(Uint8List.fromList(bytes)),
          throwsFormatException,
          reason: '$bytes',
        );
      }
    });

    test('reads OIDs and times', () {
      expect(
        DerNode.parse(derOid('1.2.840.113635.100.6.11.1')).asOid,
        '1.2.840.113635.100.6.11.1',
      );
      expect(
        DerNode.parse(derUtcTime(DateTime.utc(2031, 2, 3, 4, 5, 6))).asTime,
        DateTime.utc(2031, 2, 3, 4, 5, 6),
      );
    });
  });

  group('AppleJwsVerifier', () {
    late TestAppleChain chain;
    late AppleJwsVerifier verifier;

    setUp(() {
      chain = TestAppleChain();
      verifier = AppleJwsVerifier(trustedRoots: [chain.root]);
    });

    test('a JWS signed by the leaf of a trusted chain gives its payload', () {
      final jws = chain.signJws(appleTransaction());

      final payload = verifier.verify(jws);

      expect(payload['transactionId'], '2000000123456789');
      expect(payload['type'], 'Consumable');
    });

    test('with the real Apple root only, a test chain is not trusted', () {
      final jws = chain.signJws(appleTransaction());

      expect(
        () => AppleJwsVerifier().verify(jws),
        _rejected(ReceiptRejection.invalidReceipt),
      );
    });

    test('a changed payload (same signature) is rejected', () {
      final parts = chain.signJws(appleTransaction()).split('.');
      final forged = base64Url
          .encode(utf8.encode(jsonEncode(appleTransaction(productId: 'x'))))
          .replaceAll('=', '');

      expect(
        () => verifier.verify('${parts[0]}.$forged.${parts[2]}'),
        _rejected(ReceiptRejection.invalidReceipt),
      );
    });

    test('a signature by another key is rejected', () {
      final jws = chain.signJws(
        appleTransaction(),
        signWith: TestKey(EcCurve.p256, BigInt.from(99991)),
      );

      expect(
        () => verifier.verify(jws),
        _rejected(ReceiptRejection.invalidReceipt),
      );
    });

    test('a leaf without the App Store marker OID is rejected', () {
      final unmarked = TestAppleChain(leafMarker: false);
      final jws = unmarked.signJws(appleTransaction());

      expect(
        () => AppleJwsVerifier(trustedRoots: [unmarked.root]).verify(jws),
        _rejected(ReceiptRejection.invalidReceipt),
      );
    });

    test('an expired leaf is rejected', () {
      final expired = TestAppleChain(leafNotAfter: DateTime.utc(2021));
      final jws = expired.signJws(appleTransaction());

      expect(
        () => AppleJwsVerifier(trustedRoots: [expired.root]).verify(jws),
        _rejected(ReceiptRejection.invalidReceipt),
      );
    });

    test(
      'a chain whose intermediate is not signed by the root is rejected',
      () {
        // Stessa forma, radice diversa: il certificato in fondo alla catena è
        // fidato, ma l'intermedio è stato firmato da un'altra radice.
        final other = TestAppleChain(
          rootKey: TestKey(EcCurve.p384, BigInt.from(0x9999)),
        );
        final jws = chain.signJws(appleTransaction());
        final parts = jws.split('.');
        final header =
            jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
                )
                as Map<String, dynamic>;
        final x5c = (header['x5c'] as List).cast<String>();
        final mixed = base64Url
            .encode(
              utf8.encode(
                jsonEncode({
                  'alg': 'ES256',
                  'x5c': [x5c[0], x5c[1], base64.encode(other.root)],
                }),
              ),
            )
            .replaceAll('=', '');

        expect(
          () => AppleJwsVerifier(
            trustedRoots: [chain.root, other.root],
          ).verify('$mixed.${parts[1]}.${parts[2]}'),
          _rejected(ReceiptRejection.invalidReceipt),
        );
      },
    );

    test('alg other than ES256, short chains and garbage are rejected', () {
      String header(Object json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      final good = chain.signJws(appleTransaction()).split('.');

      for (final jws in [
        '${header({'alg': 'HS256'})}.${good[1]}.${good[2]}',
        '${header({
          'alg': 'ES256',
          'x5c': [base64.encode(chain.leaf), base64.encode(chain.root)],
        })}.${good[1]}.${good[2]}',
        'not-a-jws',
        'a.b.c',
      ]) {
        expect(
          () => verifier.verify(jws),
          _rejected(ReceiptRejection.invalidReceipt),
          reason: jws,
        );
      }
    });
  });
}
