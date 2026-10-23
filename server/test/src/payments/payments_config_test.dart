import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:threemojo_server/src/payments/payments.dart';
import 'package:threemojo_server/src/payments/payments_config.dart';
import 'package:threemojo_server/src/paywall_store.dart';

void main() {
  late Directory dir;
  late String accountPath;
  late String keyPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('payments_config_test');
    accountPath = '${dir.path}/service_account.json';
    File(accountPath).writeAsStringSync(
      jsonEncode({'type': 'service_account', 'client_email': 'x@y'}),
    );
    keyPath = '${dir.path}/AuthKey.p8';
    File(keyPath).writeAsStringSync('-----BEGIN PRIVATE KEY-----...');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, String> fullReal() => {
    'PAYMENTS_MODE': 'real',
    'APPLE_BUNDLE_ID': 'it.ameol.raen',
    'APPLE_PRODUCT_ID': 'raen.unlock_2h',
    'APPLE_ENVIRONMENT': 'production',
    'GOOGLE_PACKAGE_NAME': 'it.ameol.raen',
    'GOOGLE_PRODUCT_ID': 'raen.unlock_2h',
    'GOOGLE_SERVICE_ACCOUNT_JSON_PATH': accountPath,
  };

  test('without PAYMENTS_MODE it is fake, and says so', () {
    final config = PaymentsConfig.fromEnvironment({});

    expect(config.mode, PaymentsMode.fake);
    expect(config.apple, isNull);
    expect(config.google, isNull);
    expect(config.problems.single, contains('PAYMENTS_MODE non impostato'));
  });

  test('without PAYMENTS_MODE a public server (TLS or proxy) is real', () {
    for (final env in [
      {'TLS_CERT_PATH': '/etc/cert.pem', 'TLS_KEY_PATH': '/etc/key.pem'},
      {'TRUSTED_PROXY': '10.0.0.1'},
    ]) {
      final config = PaymentsConfig.fromEnvironment(env);

      expect(config.mode, PaymentsMode.real, reason: '$env');
      expect(
        config.problems.first,
        contains('mai il finto per dimenticanza'),
        reason: '$env',
      );
    }
  });

  test('an explicit PAYMENTS_MODE=fake is honoured even behind TLS', () {
    final config = PaymentsConfig.fromEnvironment({
      'PAYMENTS_MODE': 'fake',
      'TLS_CERT_PATH': '/etc/cert.pem',
      'TLS_KEY_PATH': '/etc/key.pem',
    });

    expect(config.mode, PaymentsMode.fake);
  });

  test('an unknown mode never falls back to fake', () {
    final config = PaymentsConfig.fromEnvironment({'PAYMENTS_MODE': 'test'});

    expect(config.mode, PaymentsMode.real);
    expect(config.problems.first, contains('non valido'));
  });

  test('real mode without credentials: both platforms off, with a clear '
      'message for each', () {
    final config = PaymentsConfig.fromEnvironment({'PAYMENTS_MODE': 'real'});

    expect(config.apple, isNull);
    expect(config.google, isNull);
    expect(config.problems.join('\n'), contains('APPLE_BUNDLE_ID'));
    expect(
      config.problems.join('\n'),
      contains('GOOGLE_SERVICE_ACCOUNT_JSON_PATH'),
    );
  });

  test('real mode, fully configured: both platforms on, notifications off '
      'by default', () {
    final config = PaymentsConfig.fromEnvironment(fullReal());
    final payments = Payments.fromConfig(
      config,
      paywallStore: PaywallStore.withClock(DateTime.now),
    );

    expect(config.problems, isEmpty);
    expect(config.apple?.productId, 'raen.unlock_2h');
    expect(config.apple?.acceptedEnvironments, {'Production', 'Sandbox'});
    expect(config.apple?.apiCredentials, isNull);
    expect(config.google?.packageName, 'it.ameol.raen');
    expect(payments.appleNotifications, isNull);
    expect(payments.googleNotifications, isNull);
  });

  test('notifications turn on only when asked', () {
    final config = PaymentsConfig.fromEnvironment({
      ...fullReal(),
      'APPLE_NOTIFICATIONS_ENABLED': 'true',
      'GOOGLE_RTDN_TOKEN': 'x' * 40,
    });
    final payments = Payments.fromConfig(
      config,
      paywallStore: PaywallStore.withClock(DateTime.now),
    );

    expect(payments.appleNotifications, isNotNull);
    expect(payments.googleNotifications, isNotNull);
  });

  test('a short RTDN token keeps Google notifications off', () {
    final config = PaymentsConfig.fromEnvironment({
      ...fullReal(),
      'GOOGLE_RTDN_TOKEN': 'short',
    });

    expect(config.google?.rtdnToken, isNull);
    expect(config.problems.single, contains('GOOGLE_RTDN_TOKEN'));
  });

  test('a service account file that is not one turns Android off', () {
    File(accountPath).writeAsStringSync('{"type": "authorized_user"}');

    final config = PaymentsConfig.fromEnvironment(fullReal());

    expect(config.google, isNull);
    expect(config.apple, isNotNull);
  });

  test('Apple API credentials need all three variables', () {
    final partial = PaymentsConfig.fromEnvironment({
      ...fullReal(),
      'APPLE_KEY_ID': 'ABC',
    });
    final complete = PaymentsConfig.fromEnvironment({
      ...fullReal(),
      'APPLE_KEY_ID': 'ABC',
      'APPLE_ISSUER_ID': 'issuer',
      'APPLE_PRIVATE_KEY_PATH': keyPath,
    });

    expect(partial.apple?.apiCredentials, isNull);
    expect(partial.problems.single, contains('APPLE_ISSUER_ID'));
    expect(complete.apple?.apiCredentials?.keyId, 'ABC');
  });
}
