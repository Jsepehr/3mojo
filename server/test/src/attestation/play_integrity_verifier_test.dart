import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:threemojo_server/src/attestation/attestation_challenge.dart';
import 'package:threemojo_server/src/attestation/attestation_verifier.dart';
import 'package:threemojo_server/src/attestation/play_integrity_api.dart';
import 'package:threemojo_server/src/attestation/play_integrity_verifier.dart';

const _package = 'com.threemojo.app';
const _nonce = 'nonce-of-this-socket';
final _now = DateTime.utc(2026, 10, 23, 12);

/// Un `tokenPayloadExternal` come lo risponde Google per una Standard
/// request.
Map<String, dynamic> _verdict({
  String requestPackage = _package,
  String appPackage = _package,
  String? requestHash,
  Object? timestampMillis,
  String appVerdict = 'PLAY_RECOGNIZED',
  List<String> device = const ['MEETS_DEVICE_INTEGRITY'],
}) => {
  'requestDetails': {
    'requestPackageName': requestPackage,
    'requestHash': requestHash ?? AttestationChallenge.requestHash(_nonce),
    'timestampMillis':
        timestampMillis ??
        '${_now.subtract(const Duration(seconds: 5)).millisecondsSinceEpoch}',
  },
  'appIntegrity': {
    'appRecognitionVerdict': appVerdict,
    'packageName': appPackage,
    'certificateSha256Digest': ['abc'],
    'versionCode': '1',
  },
  'deviceIntegrity': {'deviceRecognitionVerdict': device},
  'accountDetails': {'appLicensingVerdict': 'LICENSED'},
};

class _FakeApi implements PlayIntegrityApi {
  _FakeApi(this.response);

  Map<String, dynamic> response;
  final tokens = <String>[];

  @override
  Future<Map<String, dynamic>> decodeIntegrityToken(String token) async {
    tokens.add(token);
    return response;
  }
}

Matcher _rejected(AttestationRejection reason) => throwsA(
  isA<AttestationRejectedException>().having((e) => e.reason, 'reason', reason),
);

void main() {
  PlayIntegrityVerifier verifier(Map<String, dynamic> response) =>
      PlayIntegrityVerifier(
        packageName: _package,
        api: _FakeApi(response),
        now: () => _now,
      );

  group('PlayIntegrityVerifier', () {
    test('a recent verdict for our app, this nonce and an integral device '
        'is valid', () async {
      final api = _FakeApi(_verdict());
      final v = PlayIntegrityVerifier(
        packageName: _package,
        api: api,
        now: () => _now,
      );
      await expectLater(
        v.verify(const PlayIntegrityEvidence('token-abc'), nonce: _nonce),
        completes,
      );
      expect(api.tokens, ['token-abc']);
    });

    test('the request hash is hex(SHA-256(utf8(nonce)))', () {
      expect(
        AttestationChallenge.requestHash('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('a token for another nonce (another socket) is refused', () async {
      await expectLater(
        verifier(
          _verdict(requestHash: AttestationChallenge.requestHash('other')),
        ).verify(const PlayIntegrityEvidence('t'), nonce: _nonce),
        _rejected(AttestationRejection.wrongNonce),
      );
    });

    test('another package is refused', () async {
      for (final verdict in [
        _verdict(requestPackage: 'com.evil.app'),
        _verdict(appPackage: 'com.evil.app'),
      ]) {
        await expectLater(
          verifier(
            verdict,
          ).verify(const PlayIntegrityEvidence('t'), nonce: _nonce),
          _rejected(AttestationRejection.wrongApp),
        );
      }
    });

    test('a device without MEETS_DEVICE_INTEGRITY is refused (basic integrity '
        'alone is not enough)', () async {
      for (final device in [
        <String>[],
        ['MEETS_BASIC_INTEGRITY'],
      ]) {
        await expectLater(
          verifier(
            _verdict(device: device),
          ).verify(const PlayIntegrityEvidence('t'), nonce: _nonce),
          _rejected(AttestationRejection.deviceNotTrusted),
        );
      }
    });

    test('an app not recognized by Play is refused', () async {
      for (final verdict in ['UNRECOGNIZED_VERSION', 'UNEVALUATED']) {
        await expectLater(
          verifier(
            _verdict(appVerdict: verdict),
          ).verify(const PlayIntegrityEvidence('t'), nonce: _nonce),
          _rejected(AttestationRejection.unrecognizedApp),
        );
      }
    });

    test('an old or future verdict is refused', () async {
      for (final offset in [
        const Duration(minutes: -3),
        const Duration(minutes: 2),
      ]) {
        await expectLater(
          verifier(
            _verdict(timestampMillis: _now.add(offset).millisecondsSinceEpoch),
          ).verify(const PlayIntegrityEvidence('t'), nonce: _nonce),
          _rejected(AttestationRejection.stale),
        );
      }
    });

    test('an incomplete verdict is malformed', () async {
      await expectLater(
        verifier({
          'requestDetails': <String, dynamic>{},
        }).verify(const PlayIntegrityEvidence('t'), nonce: _nonce),
        _rejected(AttestationRejection.malformed),
      );
      await expectLater(
        verifier(
          _verdict(timestampMillis: 'yesterday'),
        ).verify(const PlayIntegrityEvidence('t'), nonce: _nonce),
        _rejected(AttestationRejection.malformed),
      );
    });

    test('evidence of another platform is malformed', () async {
      await expectLater(
        verifier(
          _verdict(),
        ).verify(const FakeAttestationEvidence('t'), nonce: _nonce),
        _rejected(AttestationRejection.malformed),
      );
    });
  });

  group('PlayIntegrityApiImpl', () {
    PlayIntegrityApiImpl api(MockClient client) => PlayIntegrityApiImpl(
      packageName: _package,
      serviceAccountJson: '{}',
      clientFactory: () async => client,
    );

    test('calls decodeIntegrityToken for the package and returns the '
        'payload', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({'tokenPayloadExternal': _verdict()}),
          200,
        );
      });
      final payload = await api(client).decodeIntegrityToken('tok');
      expect(seen.method, 'POST');
      expect(
        seen.url.toString(),
        'https://playintegrity.googleapis.com/v1/$_package:decodeIntegrityToken',
      );
      expect(jsonDecode(seen.body), {'integrityToken': 'tok'});
      expect(payload['appIntegrity'], isA<Map<String, dynamic>>());
    });

    test('400 is a refused token, everything else is "unavailable"', () async {
      await expectLater(
        api(
          MockClient((_) async => http.Response('', 400)),
        ).decodeIntegrityToken('tok'),
        _rejected(AttestationRejection.malformed),
      );
      for (final status in [401, 403, 429, 500, 503]) {
        await expectLater(
          api(
            MockClient((_) async => http.Response('', status)),
          ).decodeIntegrityToken('tok'),
          throwsA(isA<AttestationUnavailableException>()),
        );
      }
      await expectLater(
        api(
          MockClient((_) async => http.Response('not json', 200)),
        ).decodeIntegrityToken('tok'),
        throwsA(isA<AttestationUnavailableException>()),
      );
      await expectLater(
        api(
          MockClient((_) async => throw http.ClientException('offline')),
        ).decodeIntegrityToken('tok'),
        throwsA(isA<AttestationUnavailableException>()),
      );
    });
  });
}
