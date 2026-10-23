import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:threemojo_server/src/payments/apple_jws_verifier.dart';
import 'package:threemojo_server/src/payments/ecdsa.dart';

/// Una piccola PKI **di test** con la stessa forma di quella di Apple
/// (radice P-384 → intermedio → foglia P-256, OID Apple sulle estensioni),
/// per verificare `AppleJwsVerifier` senza account né certificati veri.

// --- DER (solo scrittura, per costruire i certificati) ---

Uint8List tlv(int tag, List<int> content) {
  final length = content.length;
  final List<int> lengthBytes;
  if (length < 0x80) {
    lengthBytes = [length];
  } else {
    final bytes = <int>[];
    var rest = length;
    while (rest > 0) {
      bytes.insert(0, rest & 0xff);
      rest >>= 8;
    }
    lengthBytes = [0x80 | bytes.length, ...bytes];
  }
  return Uint8List.fromList([tag, ...lengthBytes, ...content]);
}

Uint8List seq(List<List<int>> items) =>
    tlv(0x30, [for (final i in items) ...i]);

Uint8List setOf(List<List<int>> items) =>
    tlv(0x31, [for (final i in items) ...i]);

Uint8List explicit(int n, List<int> content) => tlv(0xa0 | n, content);

Uint8List derInt(BigInt value) {
  var bytes = encodeUnsigned(value, (value.bitLength + 7) ~/ 8 + 1);
  // Toglie gli zeri iniziali in più, ma ne lascia uno se serve il segno.
  while (bytes.length > 1 && bytes[0] == 0 && bytes[1] < 0x80) {
    bytes = Uint8List.sublistView(bytes, 1);
  }
  return tlv(0x02, bytes);
}

Uint8List derOid(String dotted) {
  final parts = dotted.split('.').map(int.parse).toList();
  final out = <int>[parts[0] * 40 + parts[1]];
  for (final part in parts.skip(2)) {
    final chunk = <int>[part & 0x7f];
    var rest = part >> 7;
    while (rest > 0) {
      chunk.insert(0, 0x80 | (rest & 0x7f));
      rest >>= 7;
    }
    out.addAll(chunk);
  }
  return tlv(0x06, out);
}

Uint8List derBitString(List<int> bytes) => tlv(0x03, [0, ...bytes]);

Uint8List derOctets(List<int> bytes) => tlv(0x04, bytes);

Uint8List derUtcTime(DateTime time) {
  final t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return tlv(
    0x17,
    ascii.encode(
      '${two(t.year % 100)}${two(t.month)}${two(t.day)}'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}Z',
    ),
  );
}

Uint8List name(String commonName) => seq([
  setOf([
    seq([derOid('2.5.4.3'), tlv(0x0c, utf8.encode(commonName))]),
  ]),
]);

// --- Chiavi e firme ---

class TestKey {
  TestKey(this.curve, this.d);

  final EcCurve curve;
  final BigInt d;

  Uint8List get publicPoint => (curve.domain.G * d)!.getEncoded(false);

  /// Firma DER (per i certificati).
  Uint8List signDer(Uint8List message, EcdsaHash hash) {
    final digest = hash.newDigest();
    final signer =
        ECDSASigner(
          hash.newDigest(),
          HMac(digest, hash == EcdsaHash.sha256 ? 64 : 128),
        )..init(
          true,
          PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(d, curve.domain)),
        );
    final signature = signer.generateSignature(message) as ECSignature;
    return seq([derInt(signature.r), derInt(signature.s)]);
  }

  /// La stessa chiave come PEM PKCS#8 (il formato dei `.p8` di Apple).
  String toPkcs8Pem() {
    final ecPrivateKey = seq([
      derInt(BigInt.one),
      derOctets(encodeUnsigned(d, curve.coordinateLength)),
    ]);
    final der = seq([
      derInt(BigInt.zero),
      seq([derOid(ecPublicKeyOid), derOid(curve.oid)]),
      derOctets(ecPrivateKey),
    ]);
    return '-----BEGIN PRIVATE KEY-----\n${base64.encode(der)}\n'
        '-----END PRIVATE KEY-----\n';
  }
}

Uint8List buildCertificate({
  required String subject,
  required String issuer,
  required TestKey subjectKey,
  required TestKey issuerKey,
  required bool isCa,
  Set<String> markerOids = const {},
  DateTime? notBefore,
  DateTime? notAfter,
  int serial = 1,
}) {
  final hash = issuerKey.curve == EcCurve.p384
      ? EcdsaHash.sha384
      : EcdsaHash.sha256;
  final algorithm = seq([derOid(hash.oid)]);
  final extensions = seq([
    seq([
      derOid('2.5.29.19'),
      tlv(0x01, [0xff]),
      derOctets(
        seq([
          if (isCa) tlv(0x01, [0xff]),
        ]),
      ),
    ]),
    for (final oid in markerOids) seq([derOid(oid), derOctets(tlv(0x05, []))]),
  ]);
  final tbs = seq([
    explicit(0, derInt(BigInt.two)),
    derInt(BigInt.from(serial)),
    algorithm,
    name(issuer),
    seq([
      derUtcTime(notBefore ?? DateTime.utc(2020)),
      derUtcTime(notAfter ?? DateTime.utc(2045)),
    ]),
    name(subject),
    seq([
      seq([derOid(ecPublicKeyOid), derOid(subjectKey.curve.oid)]),
      derBitString(subjectKey.publicPoint),
    ]),
    explicit(3, extensions),
  ]);
  return seq([tbs, algorithm, derBitString(issuerKey.signDer(tbs, hash))]);
}

/// Radice, intermedio e foglia di test con le stesse estensioni di Apple.
class TestAppleChain {
  TestAppleChain({
    bool leafMarker = true,
    DateTime? leafNotAfter,
    TestKey? rootKey,
  }) : rootKey = rootKey ?? TestKey(EcCurve.p384, BigInt.from(0x1234567)) {
    root = buildCertificate(
      subject: 'Test Root CA - G3',
      issuer: 'Test Root CA - G3',
      subjectKey: this.rootKey,
      issuerKey: this.rootKey,
      isCa: true,
    );
    intermediate = buildCertificate(
      subject: 'Test WWDR CA',
      issuer: 'Test Root CA - G3',
      subjectKey: intermediateKey,
      issuerKey: this.rootKey,
      isCa: true,
      markerOids: {AppleJwsVerifier.intermediateMarkerOid},
      serial: 2,
    );
    leaf = buildCertificate(
      subject: 'Test App Store Signing',
      issuer: 'Test WWDR CA',
      subjectKey: leafKey,
      issuerKey: intermediateKey,
      isCa: false,
      markerOids: {if (leafMarker) AppleJwsVerifier.leafMarkerOid},
      notAfter: leafNotAfter,
      serial: 3,
    );
  }

  final TestKey rootKey;
  final TestKey intermediateKey = TestKey(EcCurve.p384, BigInt.from(0x7654321));
  final TestKey leafKey = TestKey(EcCurve.p256, BigInt.from(0xabcdef01));
  late final Uint8List root;
  late final Uint8List intermediate;
  late final Uint8List leaf;

  /// Un JWS compatto firmato dalla foglia, con la catena in `x5c`.
  String signJws(Map<String, Object?> payload, {TestKey? signWith}) {
    String enc(Object json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    final header = enc({
      'alg': 'ES256',
      'x5c': [
        base64.encode(leaf),
        base64.encode(intermediate),
        base64.encode(root),
      ],
    });
    final body = enc(payload);
    final signed = '$header.$body';
    final key = EcPrivateKey(EcCurve.p256, (signWith ?? leafKey).d);
    final signature = key.signEs256(Uint8List.fromList(ascii.encode(signed)));
    return '$signed.${base64Url.encode(signature).replaceAll('=', '')}';
  }
}

/// Una transazione consumabile come quelle dell'App Store.
Map<String, Object?> appleTransaction({
  String transactionId = '2000000123456789',
  String bundleId = 'it.ameol.raen',
  String productId = 'raen.unlock_2h',
  String environment = 'Sandbox',
  String type = 'Consumable',
  DateTime? purchaseDate,
  int? revocationDate,
}) => {
  'transactionId': transactionId,
  'originalTransactionId': transactionId,
  'bundleId': bundleId,
  'productId': productId,
  'purchaseDate': (purchaseDate ?? DateTime.now()).millisecondsSinceEpoch,
  'quantity': 1,
  'type': type,
  'environment': environment,
  'signedDate': DateTime.now().millisecondsSinceEpoch,
  'revocationDate': ?revocationDate,
};
