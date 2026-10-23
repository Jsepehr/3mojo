import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/attestation/attestation_data_source_impl.dart';
import 'package:threemojo_app/core/attestation/device_attestation.dart';
import 'package:threemojo_app/core/errors/exceptions.dart';

const _channel = MethodChannel('raen/attestation-test');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  AttestationDataSourceImpl dataSource(
    TargetPlatform platform, {
    int projectNumber = 123456789012,
    bool isWeb = false,
  }) => AttestationDataSourceImpl(
    channel: _channel,
    platform: platform,
    isWeb: isWeb,
    cloudProjectNumber: projectNumber,
  );

  test('the hashes are the same the server computes', () {
    expect(
      DeviceAttestation.requestHash('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      DeviceAttestation.clientDataHash('abc'),
      sha256.convert(utf8.encode('abc')).bytes,
    );
  });

  test('Android asks Play Integrity with requestHash and the project '
      'number', () async {
    answer((_) async => 'play-token');
    final attestation = await dataSource(TargetPlatform.android).attest('n-1');

    expect(calls.single.method, 'playIntegrityToken');
    expect(calls.single.arguments, {
      'requestHash': DeviceAttestation.requestHash('n-1'),
      'cloudProjectNumber': 123456789012,
    });
    expect(attestation.toJson(), {
      'platform': 'android',
      'token': 'play-token',
    });
  });

  test('Android without the Google Cloud project number does not even '
      'try', () async {
    answer((_) async => 'play-token');
    await expectLater(
      dataSource(TargetPlatform.android, projectNumber: 0).attest('n-1'),
      throwsA(isA<AttestationUnavailableException>()),
    );
    expect(calls, isEmpty);
  });

  test('iOS asks App Attest with clientDataHash and sends keyId and the '
      'attestation in base64', () async {
    answer(
      (_) async => {
        'keyId': 'a2V5LWlk',
        'attestationObject': Uint8List.fromList([1, 2, 3]),
      },
    );
    final attestation = await dataSource(TargetPlatform.iOS).attest('n-1');

    expect(calls.single.method, 'appAttest');
    expect(
      (calls.single.arguments as Map)['clientDataHash'],
      DeviceAttestation.clientDataHash('n-1'),
    );
    expect(attestation.toJson(), {
      'platform': 'ios',
      'keyId': 'a2V5LWlk',
      'attestationObject': base64.encode([1, 2, 3]),
    });
  });

  test('"not supported" (iOS simulator) and every native error become '
      'AttestationUnavailableException', () async {
    answer((_) async => throw PlatformException(code: 'UNSUPPORTED'));
    await expectLater(
      dataSource(TargetPlatform.iOS).attest('n-1'),
      throwsA(isA<AttestationUnavailableException>()),
    );
    answer((_) async => {'keyId': 'x'});
    await expectLater(
      dataSource(TargetPlatform.iOS).attest('n-1'),
      throwsA(isA<AttestationUnavailableException>()),
    );
    answer((_) async => null);
    await expectLater(
      dataSource(TargetPlatform.android).attest('n-1'),
      throwsA(isA<AttestationUnavailableException>()),
    );
  });

  test('no channel (tests, desktop) and the web are "unavailable"', () async {
    await expectLater(
      dataSource(TargetPlatform.android).attest('n-1'),
      throwsA(isA<AttestationUnavailableException>()),
    );
    await expectLater(
      dataSource(TargetPlatform.macOS).attest('n-1'),
      throwsA(isA<AttestationUnavailableException>()),
    );
    await expectLater(
      dataSource(TargetPlatform.iOS, isWeb: true).attest('n-1'),
      throwsA(isA<AttestationUnavailableException>()),
    );
  });
}
