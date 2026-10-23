import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'der.dart';

/// Le due curve usate dalla catena di Apple: P-256 (foglia, firme ES256 di
/// transazioni e notifiche, chiavi `.p8` delle API) e P-384 (radice Apple
/// Root CA - G3).
enum EcCurve {
  p256('1.2.840.10045.3.1.7', 32),
  p384('1.3.132.0.34', 48);

  const EcCurve(this.oid, this.coordinateLength);

  final String oid;

  /// Byte di una coordinata (e di `r`/`s` in una firma JOSE).
  final int coordinateLength;

  ECDomainParameters get domain => switch (this) {
    EcCurve.p256 => ECCurve_secp256r1(),
    EcCurve.p384 => ECCurve_secp384r1(),
  };

  static EcCurve? fromOid(String oid) {
    for (final curve in values) {
      if (curve.oid == oid) return curve;
    }
    return null;
  }
}

/// Gli hash ammessi nelle firme ECDSA dei certificati e dei JWS.
enum EcdsaHash {
  sha256('1.2.840.10045.4.3.2'),
  sha384('1.2.840.10045.4.3.3');

  const EcdsaHash(this.oid);

  /// OID dell'algoritmo di firma `ecdsa-with-SHAxxx` nei certificati.
  final String oid;

  Digest newDigest() => switch (this) {
    EcdsaHash.sha256 => SHA256Digest(),
    EcdsaHash.sha384 => SHA384Digest(),
  };

  static EcdsaHash? fromSignatureOid(String oid) {
    for (final hash in values) {
      if (hash.oid == oid) return hash;
    }
    return null;
  }
}

/// Una chiave pubblica EC (punto non compresso `04 || X || Y`).
class EcPublicKey {
  EcPublicKey(this.curve, this.point);

  final EcCurve curve;
  final Uint8List point;

  /// `true` se ([r], [s]) è una firma valida di [message] con questa chiave.
  /// Mai un'eccezione per una firma o una chiave malformata: `false`.
  bool verify(
    Uint8List message, {
    required EcdsaHash hash,
    required BigInt r,
    required BigInt s,
  }) {
    try {
      final domain = curve.domain;
      final q = domain.curve.decodePoint(point);
      if (q == null || q.isInfinity) return false;
      final signer = ECDSASigner(hash.newDigest())
        ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(q, domain)));
      return signer.verifySignature(message, ECSignature(r, s));
    } catch (_) {
      return false;
    }
  }

  /// Firma JOSE (`r || s`, ognuno lungo [EcCurve.coordinateLength]).
  bool verifyJose(Uint8List message, Uint8List raw, EcdsaHash hash) {
    final length = curve.coordinateLength;
    if (raw.length != 2 * length) return false;
    return verify(
      message,
      hash: hash,
      r: _unsigned(Uint8List.sublistView(raw, 0, length)),
      s: _unsigned(Uint8List.sublistView(raw, length)),
    );
  }

  /// Firma DER (`SEQUENCE { INTEGER r, INTEGER s }`), come nei certificati.
  bool verifyDer(Uint8List message, Uint8List der, EcdsaHash hash) {
    try {
      final parts = DerNode.parse(der).expectTag(DerNode.tagSequence).children;
      if (parts.length != 2) return false;
      return verify(
        message,
        hash: hash,
        r: parts[0].asUnsignedInt,
        s: parts[1].asUnsignedInt,
      );
    } on FormatException {
      return false;
    }
  }
}

/// Una chiave privata P-256 (es. la chiave `.p8` delle API App Store) che
/// firma in ES256 deterministico (RFC 6979: nessun generatore casuale da
/// cui dipendere).
class EcPrivateKey {
  EcPrivateKey(this.curve, this.d);

  /// Da un PEM PKCS#8 (`-----BEGIN PRIVATE KEY-----`), il formato dei file
  /// `.p8` scaricati da App Store Connect.
  factory EcPrivateKey.fromPkcs8Pem(String pem) {
    final der = decodePem(pem, 'PRIVATE KEY');
    final info = DerNode.parse(der).expectTag(DerNode.tagSequence).children;
    if (info.length < 3) throw const FormatException('PKCS#8 non valido');
    final algorithm = info[1].expectTag(DerNode.tagSequence).children;
    if (algorithm.length != 2 ||
        algorithm[0].asOid != _ecPublicKeyOid ||
        EcCurve.fromOid(algorithm[1].asOid) == null) {
      throw const FormatException('PKCS#8: non è una chiave EC supportata');
    }
    final curve = EcCurve.fromOid(algorithm[1].asOid)!;
    final ecKey = DerNode.parse(
      info[2].expectTag(DerNode.tagOctetString).content,
    ).expectTag(DerNode.tagSequence).children;
    if (ecKey.length < 2) throw const FormatException('ECPrivateKey');
    final dBytes = ecKey[1].expectTag(DerNode.tagOctetString).content;
    return EcPrivateKey(curve, _unsigned(dBytes));
  }

  final EcCurve curve;
  final BigInt d;

  /// Firma JOSE `r || s` di [message] con SHA-256 (ES256).
  Uint8List signEs256(Uint8List message) {
    final domain = curve.domain;
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(d, domain)));
    final signature = signer.generateSignature(message) as ECSignature;
    final length = curve.coordinateLength;
    return Uint8List.fromList([
      ...encodeUnsigned(signature.r, length),
      ...encodeUnsigned(signature.s, length),
    ]);
  }
}

const _ecPublicKeyOid = '1.2.840.10045.2.1';

/// OID di `id-ecPublicKey` nelle `SubjectPublicKeyInfo`.
const ecPublicKeyOid = _ecPublicKeyOid;

BigInt _unsigned(Uint8List bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

/// [value] in big-endian su esattamente [length] byte.
Uint8List encodeUnsigned(BigInt value, int length) {
  final out = Uint8List(length);
  var rest = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest = rest >> 8;
  }
  if (rest != BigInt.zero) throw ArgumentError('Valore troppo grande');
  return out;
}

/// Il contenuto binario di un blocco PEM `-----BEGIN [label]-----`.
Uint8List decodePem(String pem, String label) {
  final match = RegExp(
    '-----BEGIN $label-----([A-Za-z0-9+/=\\s]+)-----END $label-----',
  ).firstMatch(pem);
  if (match == null) throw FormatException('PEM: manca il blocco $label');
  final body = match.group(1)!.replaceAll(RegExp(r'\s'), '');
  try {
    return base64.decode(body);
  } on FormatException {
    throw const FormatException('PEM: base64 non valido');
  }
}
