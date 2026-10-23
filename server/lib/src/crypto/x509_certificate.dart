import 'dart:typed_data';

import 'package:pointycastle/export.dart' show SHA256Digest;

import 'der.dart';
import 'ecdsa.dart';

/// Un certificato X.509 letto quanto basta per verificare una catena di
/// certificati **EC** (quelle di Apple per le transazioni firmate e per App
/// Attest): chi l'ha emesso, chi è, quando vale, la chiave pubblica, le
/// estensioni (con il loro valore grezzo) e la firma dell'emittente.
///
/// Non è una libreria X.509 generale: certificati con chiavi non EC, nomi
/// o estensioni insoliti vengono letti ma **non** saranno mai considerati
/// validi da [isSignedBy] (chiave pubblica assente → `false`).
class X509Certificate {
  X509Certificate._({
    required this.der,
    required this.tbs,
    required this.signatureAlgorithmOid,
    required this.signature,
    required this.issuer,
    required this.subject,
    required this.notBefore,
    required this.notAfter,
    required this.publicKey,
    required this.extensionOids,
    required this.extensionValues,
    required this.isCertificateAuthority,
  });

  /// Lancia [FormatException] se [der] non è un certificato leggibile.
  factory X509Certificate.parse(Uint8List der) {
    final parts = DerNode.parse(der).expectTag(DerNode.tagSequence).children;
    if (parts.length != 3) throw const FormatException('X.509: struttura');
    final tbsNode = parts[0].expectTag(DerNode.tagSequence);
    final algorithm = parts[1].expectTag(DerNode.tagSequence).children;
    final signature = parts[2].asBitStringBytes;

    final fields = tbsNode.children;
    var index = 0;
    if (fields.isNotEmpty && fields[0].tag == DerNode.contextTag(0)) index++;
    // serialNumber, signature, issuer, validity, subject, subjectPublicKeyInfo
    if (fields.length < index + 6) throw const FormatException('X.509: TBS');
    index++; // serialNumber
    index++; // signature (ripetuto, controllato sotto)
    final issuer = fields[index++].expectTag(DerNode.tagSequence);
    final validity = fields[index++].expectTag(DerNode.tagSequence).children;
    if (validity.length != 2) throw const FormatException('X.509: validità');
    final subject = fields[index++].expectTag(DerNode.tagSequence);
    final spki = fields[index++].expectTag(DerNode.tagSequence).children;

    final extensionOids = <String>{};
    final extensionValues = <String, Uint8List>{};
    var isCa = false;
    for (final field in fields.skip(index)) {
      if (field.tag != DerNode.contextTag(3)) continue;
      final extensions = DerNode.parse(
        field.content,
      ).expectTag(DerNode.tagSequence).children;
      for (final extension in extensions) {
        final items = extension.expectTag(DerNode.tagSequence).children;
        if (items.length < 2) throw const FormatException('X.509: estensione');
        final oid = items[0].asOid;
        extensionOids.add(oid);
        // Un'estensione ripetuta è vietata (RFC 5280): non si sceglie quale
        // delle due credere.
        if (extensionValues.containsKey(oid)) {
          throw const FormatException('X.509: estensione ripetuta');
        }
        extensionValues[oid] = items.last
            .expectTag(DerNode.tagOctetString)
            .content;
        if (oid == _basicConstraintsOid) {
          final value = DerNode.parse(
            items.last.expectTag(DerNode.tagOctetString).content,
          ).expectTag(DerNode.tagSequence).children;
          isCa =
              value.isNotEmpty &&
              value[0].tag == DerNode.tagBoolean &&
              value[0].asBool;
        }
      }
    }

    return X509Certificate._(
      der: der,
      tbs: tbsNode.encoded,
      signatureAlgorithmOid: algorithm.isEmpty ? '' : algorithm[0].asOid,
      signature: signature,
      issuer: issuer.encoded,
      subject: subject.encoded,
      notBefore: validity[0].asTime,
      notAfter: validity[1].asTime,
      publicKey: _readEcPublicKey(spki),
      extensionOids: extensionOids,
      extensionValues: extensionValues,
      isCertificateAuthority: isCa,
    );
  }

  static EcPublicKey? _readEcPublicKey(List<DerNode> spki) {
    if (spki.length != 2) return null;
    final algorithm = spki[0].expectTag(DerNode.tagSequence).children;
    if (algorithm.length != 2 || algorithm[0].asOid != ecPublicKeyOid) {
      return null;
    }
    final curve = EcCurve.fromOid(algorithm[1].asOid);
    if (curve == null) return null;
    return EcPublicKey(curve, spki[1].asBitStringBytes);
  }

  static const _basicConstraintsOid = '2.5.29.19';

  /// Il certificato intero, così come è arrivato.
  final Uint8List der;

  /// Il `tbsCertificate` (la parte firmata dall'emittente), byte per byte.
  final Uint8List tbs;
  final String signatureAlgorithmOid;
  final Uint8List signature;

  /// Nome dell'emittente e del soggetto (DER grezzo, confrontato byte per
  /// byte: è così che si concatena una catena).
  final Uint8List issuer;
  final Uint8List subject;
  final DateTime notBefore;
  final DateTime notAfter;

  /// `null` se la chiave non è EC P-256/P-384.
  final EcPublicKey? publicKey;
  final Set<String> extensionOids;

  /// Il valore di ogni estensione (il contenuto dell'`extnValue`, cioè il
  /// DER dentro l'OCTET STRING), per OID — es. il nonce di App Attest.
  final Map<String, Uint8List> extensionValues;

  /// `basicConstraints` con `cA = true`.
  final bool isCertificateAuthority;

  /// SHA-256 del certificato, in esadecimale minuscolo.
  String get sha256Fingerprint => SHA256Digest()
      .process(der)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  bool isValidAt(DateTime time) =>
      !time.isBefore(notBefore) && !time.isAfter(notAfter);

  /// Questo certificato è firmato da [issuerCertificate]? Controlla che
  /// l'emittente dichiarato sia il suo soggetto, che sia una CA e la firma
  /// ECDSA sul `tbsCertificate`.
  bool isSignedBy(X509Certificate issuerCertificate) {
    final key = issuerCertificate.publicKey;
    final hash = EcdsaHash.fromSignatureOid(signatureAlgorithmOid);
    if (key == null || hash == null) return false;
    if (!issuerCertificate.isCertificateAuthority) return false;
    if (!_sameBytes(issuer, issuerCertificate.subject)) return false;
    return key.verifyDer(tbs, signature, hash);
  }
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
