import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:threemojo_server/src/attestation/app_attest_verifier.dart';
import 'package:threemojo_server/src/attestation/attestation_config.dart';
import 'package:threemojo_server/src/attestation/attestation_gate.dart';
import 'package:threemojo_server/src/attestation/attestation_verifier.dart';

void main() {
  late Directory temp;
  late String accountPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('attestation_config_');
    accountPath = '${temp.path}/sa.json';
    File(accountPath).writeAsStringSync(
      jsonEncode({'type': 'service_account', 'client_email': 'x@y'}),
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Map<String, String> complete(String mode) => {
    'ATTESTATION_MODE': mode,
    'GOOGLE_PACKAGE_NAME': 'com.threemojo.app',
    'GOOGLE_SERVICE_ACCOUNT_JSON_PATH': accountPath,
    'APPLE_TEAM_ID': 'ABCDE12345',
    'APPLE_BUNDLE_ID': 'com.threemojo.app',
    'APPLE_APP_ATTEST_ENVIRONMENT': 'production',
  };

  test('without variables it is off, with no problems', () {
    final config = AttestationConfig.fromEnvironment(const {});
    expect(config.mode, AttestationMode.off);
    expect(config.fatalProblem, isNull);
    expect(config.problems, isEmpty);
    expect(AttestationGate.fromConfig(config).isActive, isFalse);
  });

  test('a misspelled mode stops the server instead of guessing', () {
    final config = AttestationConfig.fromEnvironment(const {
      'ATTESTATION_MODE': 'enforced',
    });
    expect(config.fatalProblem, contains('enforced'));
  });

  test('a complete configuration mounts both verifiers', () {
    final config = AttestationConfig.fromEnvironment(complete('enforce'));
    expect(config.fatalProblem, isNull);
    expect(config.playIntegrity?.packageName, 'com.threemojo.app');
    expect(config.appAttest?.environment, AppAttestEnvironment.production);
    final gate = AttestationGate.fromConfig(config);
    expect(gate.mode, AttestationMode.enforce);
    expect(gate.platforms, {
      AttestationPlatform.android,
      AttestationPlatform.ios,
    });
  });

  test('a dedicated Play Integrity service account wins over the payments '
      'one', () {
    final env = complete('log')
      ..['PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_PATH'] = accountPath
      ..['GOOGLE_SERVICE_ACCOUNT_JSON_PATH'] = '/does/not/exist.json';
    expect(AttestationConfig.fromEnvironment(env).playIntegrity, isNotNull);
  });

  test('enforce with a platform missing does not start (never a silent '
      'refusal of every iOS/Android user)', () {
    final env = complete('enforce')..remove('APPLE_TEAM_ID');
    final config = AttestationConfig.fromEnvironment(env);
    expect(config.fatalProblem, contains('iOS'));

    final noAndroid = complete('enforce')
      ..['GOOGLE_SERVICE_ACCOUNT_JSON_PATH'] = '/does/not/exist.json';
    expect(
      AttestationConfig.fromEnvironment(noAndroid).fatalProblem,
      contains('Android'),
    );
  });

  test('log with a platform missing starts, and says so', () {
    final config = AttestationConfig.fromEnvironment(const {
      'ATTESTATION_MODE': 'log',
    });
    expect(config.fatalProblem, isNull);
    expect(config.problems, hasLength(2));
    expect(AttestationGate.fromConfig(config).platforms, isEmpty);
  });

  test('an invalid Team ID or environment leaves iOS off', () {
    for (final change in [
      {'APPLE_TEAM_ID': 'abc'},
      {'APPLE_APP_ATTEST_ENVIRONMENT': 'sandbox'},
    ]) {
      final env = complete('log')..addAll(change);
      expect(AttestationConfig.fromEnvironment(env).appAttest, isNull);
    }
  });

  test('the fake attestation works only on a server that is not public', () {
    final local = AttestationConfig.fromEnvironment(const {
      'ATTESTATION_MODE': 'enforce',
      'ATTESTATION_ALLOW_FAKE': 'true',
    });
    expect(local.allowFake, isTrue);
    expect(local.fatalProblem, isNull);
    expect(AttestationGate.fromConfig(local).platforms, {
      AttestationPlatform.fake,
    });

    final public = AttestationConfig.fromEnvironment(const {
      'ATTESTATION_MODE': 'enforce',
      'ATTESTATION_ALLOW_FAKE': 'true',
      'TRUSTED_PROXY': '10.0.0.1',
    });
    expect(public.allowFake, isFalse);
    expect(public.fatalProblem, isNotNull);
  });

  test('the per-IP limit can be changed, never to zero', () {
    expect(
      AttestationConfig.fromEnvironment({
        ...complete('log'),
        'ATTESTATION_MAX_PER_IP_PER_MINUTE': '30',
      }).maxPerIpPerMinute,
      30,
    );
    expect(
      AttestationConfig.fromEnvironment({
        ...complete('log'),
        'ATTESTATION_MAX_PER_IP_PER_MINUTE': '0',
      }).maxPerIpPerMinute,
      AttestationConfig.defaultMaxPerIpPerMinute,
    );
  });
}
