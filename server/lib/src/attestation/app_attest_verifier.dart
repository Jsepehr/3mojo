import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show SHA256Digest;

import '../crypto/cbor.dart';
import '../crypto/der.dart';
import '../crypto/ecdsa.dart';
import '../crypto/x509_certificate.dart';
import 'apple_app_attest_root.dart';
import 'attestation_challenge.dart';
import 'attestation_verifier.dart';

/// In quale ambiente di App Attest sono generate le chiavi accettate
/// (`APPLE_APP_ATTEST_ENVIRONMENT`): si riconosce dall'AAGUID nei dati
/// dell'autenticatore. Deve corrispondere all'entitlement
/// `com.apple.developer.devicecheck.appattest-environment` dell'app (e le
/// app distribuite da App Store/TestFlight usano sempre `production`).
enum AppAttestEnvironment {
  development('appattestdevelop'),
  production('appattest');

  const AppAttestEnvironment(this._aaguidText);

  final String _aaguidText;

  /// I 16 byte dell'AAGUID: il testo ASCII, completato con zeri.
  Uint8List get aaguid {
    final out = Uint8List(16);
    out.setAll(0, ascii.encode(_aaguidText));
    return out;
  }

  static AppAttestEnvironment? fromName(String? name) {
    for (final environment in values) {
      if (environment.name == name) return environment;
    }
    return null;
  }
}

/// Verifica un'**attestazione App Attest** (iOS), con i passi della guida
/// di Apple "Validating apps that connect to your server":
/// 1. l'attestation object è CBOR `{fmt: "apple-appattest", attStmt: {x5c,
///    receipt}, authData}`;
/// 2. `x5c` = [certificato della chiave, intermedio]: il primo firmato dal
///    secondo, il secondo dalla radice Apple App Attestation Root CA
///    ([AppleAppAttestRoot], inclusa), tutti validi adesso;
/// 3. `nonce = SHA-256(authData || clientDataHash)`, con `clientDataHash =
///    SHA-256(utf8(nonce del challenge))`, è uguale all'estensione
///    `1.2.840.113635.100.8.2` del certificato della chiave;
/// 4. SHA-256 della chiave pubblica di quel certificato = `keyId`;
/// 5. nei dati dell'autenticatore: RP ID hash = SHA-256 di
///    `"<APPLE_TEAM_ID>.<APPLE_BUNDLE_ID>"`, contatore = 0 (chiave appena
///    generata, mai usata), AAGUID dell'ambiente configurato, credential id
///    = `keyId`.
///
/// **Solo attestazione, niente assertion** — scelta voluta. Le assertion
/// servono a riusare la stessa chiave nel tempo: il server dovrebbe
/// ricordare chiave pubblica e contatore per `keyId`, cioè tenere un
/// identificativo stabile del dispositivo tra una sessione e l'altra —
/// proprio ciò che l'app evita (niente account, niente id permanenti).
/// Qui invece l'app genera una **chiave nuova a ogni sessione**, la attesta
/// e la dimentica; il server verifica una volta, al `hello` che apre la
/// sessione, e non conserva nulla (né `keyId` né receipt). Le riconnessioni
/// della stessa sessione non si riattestano (vedi `SocketSession`).
///
/// La `receipt` (per il "risk metric" di Apple, che conterebbe le chiavi
/// attestate dallo stesso dispositivo) non viene usata né conservata:
/// richiederebbe di tenerla e scambiarla periodicamente con Apple.
class AppAttestVerifier implements AttestationVerifier {
  AppAttestVerifier({
    required this.teamId,
    required this.bundleId,
    required this.environment,
    List<Uint8List>? trustedRoots,
    DateTime Function()? now,
  }) : _trustedRoots = trustedRoots ?? [AppleAppAttestRoot.certificate],
       _now = now ?? DateTime.now;

  final String teamId;
  final String bundleId;
  final AppAttestEnvironment environment;
  final List<Uint8List> _trustedRoots;
  final DateTime Function() _now;

  /// OID dell'estensione col nonce nel certificato della chiave.
  static const nonceExtensionOid = '1.2.840.113635.100.8.2';

  /// L'App ID con cui si calcola l'RP ID hash.
  String get appId => '$teamId.$bundleId';

  @override
  AttestationPlatform get platform => AttestationPlatform.ios;

  @override
  Future<void> verify(
    AttestationEvidence evidence, {
    required String nonce,
  }) async {
    if (evidence is! AppAttestEvidence) {
      throw const AttestationRejectedException(AttestationRejection.malformed);
    }
    verifyAttestation(
      keyId: evidence.keyId,
      attestationObject: evidence.attestationObject,
      clientDataHash: AttestationChallenge.clientDataHash(nonce),
    );
  }

  /// I passi della verifica con un `clientDataHash` già calcolato
  /// (pubblico per i test: l'esempio di Apple passa byte grezzi).
  void verifyAttestation({
    required Uint8List keyId,
    required Uint8List attestationObject,
    required Uint8List clientDataHash,
  }) {
    try {
      _verify(keyId, attestationObject, clientDataHash);
    } on FormatException catch (e) {
      throw AttestationRejectedException(AttestationRejection.malformed, '$e');
    }
  }

  void _verify(
    Uint8List keyId,
    Uint8List attestationObject,
    Uint8List clientDataHash,
  ) {
    if (keyId.length != 32) _reject(AttestationRejection.malformed, 'keyId');

    // 1. La struttura.
    final decoded = Cbor.decode(attestationObject);
    if (decoded is! Map || decoded['fmt'] != 'apple-appattest') {
      _reject(AttestationRejection.malformed, 'fmt');
    }
    final statement = decoded['attStmt'];
    final authData = decoded['authData'];
    if (statement is! Map || authData is! Uint8List) {
      _reject(AttestationRejection.malformed, 'attStmt/authData');
    }
    final x5c = statement['x5c'];
    if (x5c is! List || x5c.length != 2 || x5c.any((c) => c is! Uint8List)) {
      _reject(AttestationRejection.malformed, 'x5c');
    }

    // 2. La catena fino alla radice di Apple.
    final credential = X509Certificate.parse(x5c[0] as Uint8List);
    final intermediate = X509Certificate.parse(x5c[1] as Uint8List);
    final now = _now().toUtc();
    final root = _trustedRoots
        .map(X509Certificate.parse)
        .where(intermediate.isSignedBy)
        .firstOrNull;
    if (root == null) {
      _reject(AttestationRejection.untrustedCertificate, 'radice non fidata');
    }
    if (!credential.isSignedBy(intermediate) ||
        credential.isCertificateAuthority) {
      _reject(AttestationRejection.untrustedCertificate, 'catena');
    }
    for (final certificate in [credential, intermediate, root]) {
      if (!certificate.isValidAt(now)) {
        _reject(AttestationRejection.untrustedCertificate, 'scaduto');
      }
    }

    // 3. Il nonce lega authData e il challenge di questo socket.
    final expectedNonce = _sha256([...authData, ...clientDataHash]);
    final extension = credential.extensionValues[nonceExtensionOid];
    if (extension == null) {
      _reject(AttestationRejection.malformed, 'manca l\'estensione nonce');
    }
    if (!_sameBytes(_nonceFromExtension(extension), expectedNonce)) {
      _reject(AttestationRejection.wrongNonce);
    }

    // 4. La chiave del certificato è quella dichiarata.
    final publicKey = credential.publicKey;
    if (publicKey == null || publicKey.curve != EcCurve.p256) {
      _reject(AttestationRejection.malformed, 'chiave non P-256');
    }
    if (!_sameBytes(_sha256(publicKey.point), keyId)) {
      _reject(AttestationRejection.malformed, 'keyId diverso dalla chiave');
    }

    // 5. I dati dell'autenticatore: rpIdHash(32) | flags(1) | counter(4) |
    //    aaguid(16) | credentialIdLength(2) | credentialId | chiave COSE...
    if (authData.length < 55) {
      _reject(AttestationRejection.malformed, 'authData corto');
    }
    final rpIdHash = Uint8List.sublistView(authData, 0, 32);
    if (!_sameBytes(rpIdHash, _sha256(utf8.encode(appId)))) {
      _reject(AttestationRejection.wrongApp);
    }
    final counter = ByteData.sublistView(authData, 33, 37).getUint32(0);
    if (counter != 0) {
      _reject(AttestationRejection.wrongKeyState, 'contatore $counter');
    }
    final aaguid = Uint8List.sublistView(authData, 37, 53);
    if (!_sameBytes(aaguid, environment.aaguid)) {
      _reject(AttestationRejection.wrongKeyState, 'ambiente');
    }
    final idLength = ByteData.sublistView(authData, 53, 55).getUint16(0);
    if (authData.length < 55 + idLength) {
      _reject(AttestationRejection.malformed, 'credentialId troncato');
    }
    final credentialId = Uint8List.sublistView(authData, 55, 55 + idLength);
    if (!_sameBytes(credentialId, keyId)) {
      _reject(AttestationRejection.malformed, 'credentialId diverso');
    }
  }

  /// L'estensione è `SEQUENCE { [1] EXPLICIT OCTET STRING nonce }`.
  static Uint8List _nonceFromExtension(Uint8List extension) {
    final items = DerNode.parse(
      extension,
    ).expectTag(DerNode.tagSequence).children;
    final tagged = items
        .where((node) => node.tag == DerNode.contextTag(1))
        .firstOrNull;
    if (tagged == null) {
      throw const FormatException('estensione nonce senza [1]');
    }
    return DerNode.parse(
      tagged.content,
    ).expectTag(DerNode.tagOctetString).content;
  }

  static Never _reject(AttestationRejection reason, [String detail = '']) =>
      throw AttestationRejectedException(reason, detail);
}

Uint8List _sha256(List<int> bytes) =>
    SHA256Digest().process(Uint8List.fromList(bytes));

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
