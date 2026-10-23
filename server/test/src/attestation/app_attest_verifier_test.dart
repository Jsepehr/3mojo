import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show SHA256Digest;
import 'package:test/test.dart';
import 'package:threemojo_server/src/attestation/app_attest_verifier.dart';
import 'package:threemojo_server/src/attestation/apple_app_attest_root.dart';
import 'package:threemojo_server/src/attestation/attestation_challenge.dart';
import 'package:threemojo_server/src/attestation/attestation_verifier.dart';
import 'package:threemojo_server/src/crypto/ecdsa.dart';
import 'package:threemojo_server/src/crypto/x509_certificate.dart';

import '../payments/test_pki.dart';

Uint8List _sha256(List<int> bytes) =>
    SHA256Digest().process(Uint8List.fromList(bytes));

// --- CBOR (solo scrittura, per costruire attestation object di test) ---

List<int> _head(int major, int length) {
  if (length < 24) return [major << 5 | length];
  if (length < 0x100) return [major << 5 | 24, length];
  if (length < 0x10000) return [major << 5 | 25, length >> 8, length & 0xff];
  return [
    major << 5 | 26,
    length >> 24 & 0xff,
    length >> 16 & 0xff,
    length >> 8 & 0xff,
    length & 0xff,
  ];
}

List<int> _cbor(Object value) => switch (value) {
  final Uint8List bytes => [..._head(2, bytes.length), ...bytes],
  final String text => [
    ..._head(3, utf8.encode(text).length),
    ...utf8.encode(text),
  ],
  final List<Object> list => [
    ..._head(4, list.length),
    for (final item in list) ..._cbor(item),
  ],
  final Map<String, Object> map => [
    ..._head(5, map.length),
    for (final entry in map.entries) ...[
      ..._cbor(entry.key),
      ..._cbor(entry.value),
    ],
  ],
  _ => throw ArgumentError(value),
};

const _teamId = 'ABCDE12345';
const _bundleId = 'com.threemojo.app';
const _nonce = 'challenge-nonce-of-this-socket';
final _now = DateTime.utc(2026, 6, 1);

/// Un'attestazione App Attest con la stessa forma di quelle di Apple, ma
/// firmata da una PKI di test.
class _TestAttestation {
  _TestAttestation({
    String appId = '$_teamId.$_bundleId',
    int counter = 0,
    AppAttestEnvironment environment = AppAttestEnvironment.production,
    String nonce = _nonce,
    bool keyIdMatchesCredentialId = true,
  }) {
    rootCertificate = buildCertificate(
      subject: 'Test App Attestation Root CA',
      issuer: 'Test App Attestation Root CA',
      subjectKey: rootKey,
      issuerKey: rootKey,
      isCa: true,
    );
    final intermediate = buildCertificate(
      subject: 'Test App Attestation CA 1',
      issuer: 'Test App Attestation Root CA',
      subjectKey: intermediateKey,
      issuerKey: rootKey,
      isCa: true,
      serial: 2,
    );
    keyId = _sha256(credentialKey.publicPoint);
    final credentialId = keyIdMatchesCredentialId
        ? keyId
        : _sha256([...keyId, 1]);
    final counterBytes = ByteData(4)..setUint32(0, counter);
    final authData = Uint8List.fromList([
      ..._sha256(utf8.encode(appId)),
      0x40, // flags: attested credential data
      ...counterBytes.buffer.asUint8List(),
      ...environment.aaguid,
      0x00, credentialId.length,
      ...credentialId,
      0xa0, // chiave COSE (qui vuota: il verificatore non la legge)
    ]);
    final clientDataHash = AttestationChallenge.clientDataHash(nonce);
    final nonceValue = _sha256([...authData, ...clientDataHash]);
    final credential = buildCertificate(
      subject: 'test key',
      issuer: 'Test App Attestation CA 1',
      subjectKey: credentialKey,
      issuerKey: intermediateKey,
      isCa: false,
      serial: 3,
      notBefore: DateTime.utc(2026, 5, 30),
      notAfter: DateTime.utc(2026, 6, 2),
      extensionValues: {
        AppAttestVerifier.nonceExtensionOid: seq([
          explicit(1, derOctets(nonceValue)),
        ]),
      },
    );
    attestationObject = Uint8List.fromList(
      _cbor({
        'fmt': 'apple-appattest',
        'attStmt': {
          'x5c': [credential, intermediate],
          'receipt': Uint8List.fromList([1, 2, 3]),
        },
        'authData': authData,
      }),
    );
  }

  final rootKey = TestKey(EcCurve.p384, BigInt.from(0x51e7a11));
  final intermediateKey = TestKey(EcCurve.p384, BigInt.from(0x2468ace));
  final credentialKey = TestKey(EcCurve.p256, BigInt.from(0x13579bdf));
  late final Uint8List rootCertificate;
  late final Uint8List keyId;
  late final Uint8List attestationObject;

  AppAttestEvidence get evidence =>
      AppAttestEvidence(keyId: keyId, attestationObject: attestationObject);
}

AppAttestVerifier _verifier({
  List<Uint8List>? roots,
  String teamId = _teamId,
  AppAttestEnvironment environment = AppAttestEnvironment.production,
  DateTime? now,
}) => AppAttestVerifier(
  teamId: teamId,
  bundleId: _bundleId,
  environment: environment,
  trustedRoots: roots,
  now: () => now ?? _now,
);

Matcher _rejected(AttestationRejection reason) => throwsA(
  isA<AttestationRejectedException>().having((e) => e.reason, 'reason', reason),
);

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/src/attestation/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('Apple App Attestation Root CA (inclusa)', () {
    test('has the verified SHA-256 fingerprint and a valid self-signature', () {
      final root = X509Certificate.parse(AppleAppAttestRoot.certificate);
      expect(root.sha256Fingerprint, AppleAppAttestRoot.sha256Fingerprint);
      expect(root.isCertificateAuthority, isTrue);
      expect(root.isSignedBy(root), isTrue);
      expect(root.notAfter, DateTime.utc(2045, 3, 15));
    });
  });

  group('real attestations (Apple sample, real iPhone)', () {
    test("Apple's published sample attestation verifies against the "
        'included root', () {
      final sample = _fixture('apple-sample-attestation.json');
      final verifier = AppAttestVerifier(
        teamId: sample['appIdPrefix'] as String,
        bundleId: sample['bundleId'] as String,
        environment: AppAttestEnvironment.production,
        now: () => DateTime.parse(sample['checkTime'] as String),
      );
      expect(
        () => verifier.verifyAttestation(
          keyId: base64.decode(sample['keyId'] as String),
          attestationObject: base64.decode(sample['attestation'] as String),
          // Nell'esempio di Apple i byte del testo sono passati così come
          // sono (vedi fixtures/README.md).
          clientDataHash: Uint8List.fromList(
            utf8.encode(sample['clientDataHash'] as String),
          ),
        ),
        returnsNormally,
      );
    });

    group('an attestation from a real iPhone, same scheme as Raen', () {
      final fixture = _fixture('termakan-ios27-attestation.json');
      final appId = (fixture['appId'] as String).split('.');
      final teamId = appId.first;
      final bundleId = appId.skip(1).join('.');
      final evidence = AppAttestEvidence(
        keyId: base64.decode(fixture['keyId'] as String),
        attestationObject: base64.decode(fixture['attestation'] as String),
      );
      final challenge = fixture['challenge'] as String;
      final validTime = DateTime.utc(2026, 10, 12, 12);

      AppAttestVerifier verifier({
        String team = '',
        AppAttestEnvironment environment = AppAttestEnvironment.production,
        DateTime? now,
      }) => AppAttestVerifier(
        teamId: team.isEmpty ? teamId : team,
        bundleId: bundleId,
        environment: environment,
        now: () => now ?? validTime,
      );

      test('is valid for its challenge', () async {
        await expectLater(
          verifier().verify(evidence, nonce: challenge),
          completes,
        );
      });

      test('is refused for another challenge (nonce)', () async {
        await expectLater(
          verifier().verify(evidence, nonce: '$challenge!'),
          _rejected(AttestationRejection.wrongNonce),
        );
      });

      test('is refused for another Team ID (RP ID)', () async {
        await expectLater(
          verifier(team: 'ZZZZZ99999').verify(evidence, nonce: challenge),
          _rejected(AttestationRejection.wrongApp),
        );
      });

      test('is refused in the development environment (AAGUID)', () async {
        await expectLater(
          verifier(
            environment: AppAttestEnvironment.development,
          ).verify(evidence, nonce: challenge),
          _rejected(AttestationRejection.wrongKeyState),
        );
      });

      test('is refused once its certificate has expired', () async {
        await expectLater(
          verifier(
            now: DateTime.utc(2026, 10, 15),
          ).verify(evidence, nonce: challenge),
          _rejected(AttestationRejection.untrustedCertificate),
        );
      });
    });
  });

  group('test PKI', () {
    test('a valid chain, nonce, RP ID, counter 0 and keyId pass', () async {
      final attestation = _TestAttestation();
      await expectLater(
        _verifier(
          roots: [attestation.rootCertificate],
        ).verify(attestation.evidence, nonce: _nonce),
        completes,
      );
    });

    test('a chain that does not end at the trusted root is refused', () async {
      final attestation = _TestAttestation();
      // Radice predefinita: quella vera di Apple, che non ha firmato la PKI
      // di test.
      await expectLater(
        _verifier().verify(attestation.evidence, nonce: _nonce),
        _rejected(AttestationRejection.untrustedCertificate),
      );
      final other = TestKey(EcCurve.p384, BigInt.from(0xbad));
      final otherRoot = buildCertificate(
        subject: 'Test App Attestation Root CA',
        issuer: 'Test App Attestation Root CA',
        subjectKey: other,
        issuerKey: other,
        isCa: true,
      );
      await expectLater(
        _verifier(
          roots: [otherRoot],
        ).verify(attestation.evidence, nonce: _nonce),
        _rejected(AttestationRejection.untrustedCertificate),
      );
    });

    test('an expired credential certificate is refused', () async {
      final attestation = _TestAttestation();
      await expectLater(
        _verifier(
          roots: [attestation.rootCertificate],
          now: DateTime.utc(2026, 6, 3),
        ).verify(attestation.evidence, nonce: _nonce),
        _rejected(AttestationRejection.untrustedCertificate),
      );
    });

    test('a nonce from another challenge is refused', () async {
      final attestation = _TestAttestation(nonce: 'another socket');
      await expectLater(
        _verifier(
          roots: [attestation.rootCertificate],
        ).verify(attestation.evidence, nonce: _nonce),
        _rejected(AttestationRejection.wrongNonce),
      );
    });

    test('another app (RP ID hash) is refused', () async {
      final attestation = _TestAttestation(appId: '$_teamId.com.other.app');
      await expectLater(
        _verifier(
          roots: [attestation.rootCertificate],
        ).verify(attestation.evidence, nonce: _nonce),
        _rejected(AttestationRejection.wrongApp),
      );
    });

    test('a key already used (counter != 0) is refused', () async {
      final attestation = _TestAttestation(counter: 1);
      await expectLater(
        _verifier(
          roots: [attestation.rootCertificate],
        ).verify(attestation.evidence, nonce: _nonce),
        _rejected(AttestationRejection.wrongKeyState),
      );
    });

    test('a key of the other environment is refused', () async {
      final attestation = _TestAttestation(
        environment: AppAttestEnvironment.development,
      );
      await expectLater(
        _verifier(
          roots: [attestation.rootCertificate],
        ).verify(attestation.evidence, nonce: _nonce),
        _rejected(AttestationRejection.wrongKeyState),
      );
      await expectLater(
        _verifier(
          roots: [attestation.rootCertificate],
          environment: AppAttestEnvironment.development,
        ).verify(attestation.evidence, nonce: _nonce),
        completes,
      );
    });

    test('a keyId that is not the certified key is refused', () async {
      final attestation = _TestAttestation();
      final evidence = AppAttestEvidence(
        keyId: _sha256([1, 2, 3]),
        attestationObject: attestation.attestationObject,
      );
      await expectLater(
        _verifier(
          roots: [attestation.rootCertificate],
        ).verify(evidence, nonce: _nonce),
        _rejected(AttestationRejection.malformed),
      );
      final mismatched = _TestAttestation(keyIdMatchesCredentialId: false);
      await expectLater(
        _verifier(
          roots: [mismatched.rootCertificate],
        ).verify(mismatched.evidence, nonce: _nonce),
        _rejected(AttestationRejection.malformed),
      );
    });

    test('garbage is refused as malformed, never with another error', () async {
      final attestation = _TestAttestation();
      final verifier = _verifier(roots: [attestation.rootCertificate]);
      for (final bytes in [
        <int>[],
        [0xa0],
        _cbor({'fmt': 'packed'}),
        attestation.attestationObject.sublist(0, 200),
      ]) {
        await expectLater(
          verifier.verify(
            AppAttestEvidence(
              keyId: attestation.keyId,
              attestationObject: Uint8List.fromList(bytes),
            ),
            nonce: _nonce,
          ),
          _rejected(AttestationRejection.malformed),
        );
      }
    });
  });
}
