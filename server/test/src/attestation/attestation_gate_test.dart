import 'dart:async';

import 'package:test/test.dart';
import 'package:threemojo_server/src/attestation/attestation_challenge.dart';
import 'package:threemojo_server/src/attestation/attestation_config.dart';
import 'package:threemojo_server/src/attestation/attestation_gate.dart';
import 'package:threemojo_server/src/attestation/attestation_verifier.dart';
import 'package:threemojo_server/src/attestation/fake_attestation_verifier.dart';

/// Un verificatore Android che risponde come gli si dice.
class _ScriptedVerifier implements AttestationVerifier {
  _ScriptedVerifier(this.answer);

  Future<void> Function() answer;
  int calls = 0;

  @override
  AttestationPlatform get platform => AttestationPlatform.android;

  @override
  Future<void> verify(AttestationEvidence evidence, {required String nonce}) {
    calls++;
    return answer();
  }
}

void main() {
  late DateTime clock;
  late List<String> logLines;

  setUp(() {
    clock = DateTime.utc(2026, 10, 23, 12);
    logLines = [];
  });

  AttestationGate gate(
    AttestationMode mode, {
    AttestationVerifier? android,
    int maxPerIp = 10,
    Duration verifyTimeout = const Duration(seconds: 10),
  }) => AttestationGate(
    mode: mode,
    verifiers: {
      AttestationPlatform.fake: const FakeAttestationVerifier(),
      AttestationPlatform.android: ?android,
    },
    maxPerIpPerMinute: maxPerIp,
    verifyTimeout: verifyTimeout,
    now: () => clock,
    log: logLines.add,
  );

  Map<String, dynamic> fake(AttestationChallenge challenge) => {
    'type': 'attestation',
    'platform': 'fake',
    'token': FakeAttestationVerifier.tokenFor(challenge.nonce),
  };

  const android = {
    'type': 'attestation',
    'platform': 'android',
    'token': 'play-token',
  };

  group('challenge', () {
    test('a nonce is 32 random bytes in base64url, different every time', () {
      final g = gate(AttestationMode.enforce);
      final nonces = {for (var i = 0; i < 50; i++) g.issueChallenge().nonce};
      expect(nonces, hasLength(50));
      for (final nonce in nonces) {
        expect(nonce, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      }
    });

    test(
      'is single use: the same challenge a second time is refused',
      () async {
        final g = gate(AttestationMode.enforce);
        final challenge = g.issueChallenge();
        expect(
          await g.evaluate(
            challenge: challenge,
            message: fake(challenge),
            ip: 'a',
          ),
          AttestationDecision.allow,
        );
        expect(
          await g.evaluate(
            challenge: challenge,
            message: fake(challenge),
            ip: 'a',
          ),
          AttestationDecision.deny,
        );
        expect(g.counts[AttestationOutcome.expiredChallenge], 1);
      },
    );

    test('expires: an answer after the TTL is refused even if valid', () async {
      final g = gate(AttestationMode.enforce);
      final challenge = g.issueChallenge();
      clock = clock.add(
        AttestationChallenge.defaultTtl + const Duration(seconds: 1),
      );
      expect(
        await g.evaluate(
          challenge: challenge,
          message: fake(challenge),
          ip: 'a',
        ),
        AttestationDecision.deny,
      );
      expect(g.counts[AttestationOutcome.expiredChallenge], 1);
    });

    test('an attestation made for another socket (nonce) is refused', () async {
      final g = gate(AttestationMode.enforce);
      final mine = g.issueChallenge();
      final other = g.issueChallenge();
      expect(
        await g.evaluate(challenge: mine, message: fake(other), ip: 'a'),
        AttestationDecision.deny,
      );
      expect(g.counts[AttestationOutcome.invalid], 1);
    });
  });

  group('modes', () {
    test('off is never active', () {
      expect(gate(AttestationMode.off).isActive, isFalse);
      expect(AttestationGate.disabled().isActive, isFalse);
      expect(gate(AttestationMode.log).isActive, isTrue);
    });

    test('log lets everything through but writes the outcome', () async {
      final g = gate(AttestationMode.log);
      final c1 = g.issueChallenge();
      final c2 = g.issueChallenge();
      final c3 = g.issueChallenge();
      expect(
        await g.evaluate(challenge: c1, message: fake(c1), ip: 'a'),
        AttestationDecision.allow,
      );
      expect(
        await g.evaluate(challenge: c2, message: fake(c3), ip: 'a'),
        AttestationDecision.allow,
      );
      expect(
        await g.evaluate(
          challenge: c3,
          message: const {'type': 'attestation'},
          ip: 'a',
        ),
        AttestationDecision.allow,
      );
      expect(g.timedOut(), AttestationDecision.allow);
      expect(g.counts, {
        AttestationOutcome.valid: 1,
        AttestationOutcome.invalid: 1,
        AttestationOutcome.missing: 1,
        AttestationOutcome.timeout: 1,
      });
      expect(logLines, hasLength(4));
      expect(logLines[1], contains('invalid (wrongNonce)'));
      expect(logLines[1], contains('→ allow'));
    });

    test('enforce lets through only a valid attestation', () async {
      final g = gate(AttestationMode.enforce);
      final c1 = g.issueChallenge();
      final c2 = g.issueChallenge();
      expect(
        await g.evaluate(challenge: c1, message: fake(c1), ip: 'a'),
        AttestationDecision.allow,
      );
      expect(
        await g.evaluate(
          challenge: c2,
          message: const {'type': 'attestation'},
          ip: 'a',
        ),
        AttestationDecision.deny,
      );
      expect(g.timedOut(), AttestationDecision.deny);
    });

    test('a platform without a verifier is refused in enforce', () async {
      final g = gate(AttestationMode.enforce);
      final challenge = g.issueChallenge();
      expect(
        await g.evaluate(
          challenge: challenge,
          message: const {
            'type': 'attestation',
            'platform': 'ios',
            'keyId': 'AAAA',
            'attestationObject': 'AAAA',
          },
          ip: 'a',
        ),
        AttestationDecision.deny,
      );
      expect(g.counts[AttestationOutcome.unsupportedPlatform], 1);
    });

    test('enforce fails closed when Google is unavailable or slow', () async {
      final verifier = _ScriptedVerifier(
        () async => throw const AttestationUnavailableException('HTTP 503'),
      );
      final g = gate(
        AttestationMode.enforce,
        android: verifier,
        verifyTimeout: const Duration(milliseconds: 20),
      );
      final c1 = g.issueChallenge();
      expect(
        await g.evaluate(challenge: c1, message: android, ip: 'a'),
        AttestationDecision.deny,
      );
      verifier.answer = () => Completer<void>().future;
      final c2 = g.issueChallenge();
      expect(
        await g.evaluate(challenge: c2, message: android, ip: 'a'),
        AttestationDecision.deny,
      );
      verifier.answer = () async => throw StateError('bug');
      final c3 = g.issueChallenge();
      expect(
        await g.evaluate(challenge: c3, message: android, ip: 'a'),
        AttestationDecision.deny,
      );
      expect(g.counts[AttestationOutcome.unavailable], 3);
    });
  });

  group('limits', () {
    test('too many attestations from the same IP are not verified', () async {
      final verifier = _ScriptedVerifier(() async {});
      final g = gate(AttestationMode.enforce, android: verifier, maxPerIp: 2);
      Future<AttestationDecision> attempt(String ip) =>
          g.evaluate(challenge: g.issueChallenge(), message: android, ip: ip);

      expect(await attempt('1.1.1.1'), AttestationDecision.allow);
      expect(await attempt('1.1.1.1'), AttestationDecision.allow);
      expect(await attempt('1.1.1.1'), AttestationDecision.rateLimited);
      expect(await attempt('2.2.2.2'), AttestationDecision.allow);
      expect(verifier.calls, 3);

      clock = clock.add(const Duration(minutes: 1));
      expect(await attempt('1.1.1.1'), AttestationDecision.allow);
    });

    test('in log mode the limit only skips the verification', () async {
      final verifier = _ScriptedVerifier(() async {});
      final g = gate(AttestationMode.log, android: verifier, maxPerIp: 1);
      await g.evaluate(
        challenge: g.issueChallenge(),
        message: android,
        ip: 'a',
      );
      expect(
        await g.evaluate(
          challenge: g.issueChallenge(),
          message: android,
          ip: 'a',
        ),
        AttestationDecision.allow,
      );
      expect(verifier.calls, 1);
      expect(g.counts[AttestationOutcome.rateLimited], 1);
    });

    test('the log never contains the IP, the token or the nonce', () async {
      final g = gate(AttestationMode.log);
      final challenge = g.issueChallenge();
      await g.evaluate(
        challenge: challenge,
        message: fake(challenge),
        ip: '203.0.113.7',
      );
      final line = logLines.single;
      expect(line, isNot(contains('203.0.113.7')));
      expect(line, isNot(contains(challenge.nonce)));
      expect(line, isNot(contains(FakeAttestationVerifier.tokenPrefix)));
    });
  });

  group('evidence', () {
    test('needs a known platform and the fields of that platform', () {
      expect(AttestationEvidence.fromMessage(const {}), isNull);
      expect(
        AttestationEvidence.fromMessage(const {'platform': 'windows'}),
        isNull,
      );
      expect(
        AttestationEvidence.fromMessage(const {'platform': 'android'}),
        isNull,
      );
      expect(
        AttestationEvidence.fromMessage(const {
          'platform': 'ios',
          'keyId': 'not base64 !!',
          'attestationObject': 'AAAA',
        }),
        isNull,
      );
      expect(
        AttestationEvidence.fromMessage({
          'platform': 'android',
          'token': 'x' * (AttestationEvidence.maxFieldLength + 1),
        }),
        isNull,
      );
      final ios = AttestationEvidence.fromMessage(const {
        'platform': 'ios',
        'keyId': 'AQID',
        'attestationObject': '-_8',
      });
      expect(ios, isA<AppAttestEvidence>());
      expect((ios! as AppAttestEvidence).keyId, [1, 2, 3]);
      expect((ios as AppAttestEvidence).attestationObject, [0xfb, 0xff]);
    });
  });
}
