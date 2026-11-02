import 'dart:convert';

import 'package:test/test.dart';
import 'package:threemojo_server/src/server_environment.dart';

final _key32 = base64Encode(List.filled(32, 3));
final _token = 'a' * 32;

Map<String, String> _production([Map<String, String> overrides = const {}]) => {
  'RAEN_ENV': 'production',
  'PAYMENTS_MODE': 'real',
  'MODERATION_KEY': _key32,
  'ADMIN_TOKEN': _token,
  'PAYMENTS_TRANSACTION_HASH_KEY': _key32,
  ...overrides,
};

void main() {
  group('RAEN_ENV=production fails closed', () {
    test('a complete configuration starts', () {
      expect(ServerEnvironment.fatalProblems(_production()), isEmpty);
      expect(
        () => ServerEnvironment.requireValid(_production()),
        returnsNormally,
      );
    });

    test('PAYMENTS_MODE must be real (missing, fake and typos all refuse)', () {
      for (final mode in ['', 'fake', 'rael']) {
        final problems = ServerEnvironment.fatalProblems(
          _production({'PAYMENTS_MODE': mode}),
        );
        expect(problems.join(), contains('PAYMENTS_MODE=real'), reason: mode);
      }
    });

    test('MODERATION_KEY missing or invalid refuses', () {
      for (final key in [
        '',
        'not base64 !!',
        base64Encode([1, 2, 3]),
      ]) {
        final problems = ServerEnvironment.fatalProblems(
          _production({'MODERATION_KEY': key}),
        );
        expect(problems.join(), contains('MODERATION_KEY'), reason: key);
      }
    });

    test('ADMIN_TOKEN missing or shorter than 32 characters refuses', () {
      for (final token in ['', 'short', 'a' * 31]) {
        final problems = ServerEnvironment.fatalProblems(
          _production({'ADMIN_TOKEN': token}),
        );
        expect(problems.join(), contains('ADMIN_TOKEN'), reason: token);
      }
    });

    test('PAYMENTS_TRANSACTION_HASH_KEY must be fixed and valid', () {
      for (final key in [
        '',
        'zzz',
        base64Encode([1, 2, 3]),
      ]) {
        final problems = ServerEnvironment.fatalProblems(
          _production({'PAYMENTS_TRANSACTION_HASH_KEY': key}),
        );
        expect(
          problems.join(),
          contains('PAYMENTS_TRANSACTION_HASH_KEY'),
          reason: key,
        );
      }
    });

    test('development-only switches refuse', () {
      for (final entry in {
        'DEBUG_ENDPOINTS_TOKEN': 'x',
        'ADMIN_ALLOW_INSECURE_HTTP': 'true',
        'ATTESTATION_ALLOW_FAKE': 'true',
      }.entries) {
        final problems = ServerEnvironment.fatalProblems(
          _production({entry.key: entry.value}),
        );
        expect(problems.join(), contains(entry.key));
      }
      // An explicit "false" is harmless.
      expect(
        ServerEnvironment.fatalProblems(
          _production({'ATTESTATION_ALLOW_FAKE': 'false'}),
        ),
        isEmpty,
      );
    });

    test('every problem is reported at once, in the exception', () {
      expect(
        () => ServerEnvironment.requireValid({'RAEN_ENV': 'production'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('PAYMENTS_MODE'),
              contains('MODERATION_KEY'),
              contains('ADMIN_TOKEN'),
              contains('PAYMENTS_TRANSACTION_HASH_KEY'),
            ),
          ),
        ),
      );
    });

    test('RAEN_ENV is case-insensitive and a typo is refused', () {
      expect(
        ServerEnvironment.isProduction({'RAEN_ENV': 'Production'}),
        isTrue,
      );
      expect(ServerEnvironment.isProduction({}), isFalse);
      expect(
        ServerEnvironment.fatalProblems({'RAEN_ENV': 'prod'}).join(),
        contains('RAEN_ENV'),
      );
      expect(
        ServerEnvironment.fatalProblems({'RAEN_ENV': 'development'}),
        isEmpty,
      );
    });
  });

  group('without RAEN_ENV', () {
    test('a plain local server starts with nothing set', () {
      expect(ServerEnvironment.fatalProblems({}), isEmpty);
      expect(
        ServerEnvironment.fatalProblems({'PAYMENTS_MODE': 'fake'}),
        isEmpty,
      );
    });

    test('an explicit PAYMENTS_MODE=fake on a public server (TLS or '
        'TRUSTED_PROXY) is refused', () {
      for (final extra in [
        {'TLS_CERT_PATH': '/c.pem'},
        {'TRUSTED_PROXY': '10.0.0.2'},
      ]) {
        expect(
          ServerEnvironment.fatalProblems({
            'PAYMENTS_MODE': 'fake',
            ...extra,
          }).join(),
          contains('PAYMENTS_MODE=fake'),
        );
      }
      // Forgetting it is not "fake" (see PaymentsConfig): no refusal needed.
      expect(
        ServerEnvironment.fatalProblems({'TRUSTED_PROXY': '10.0.0.2'}),
        isEmpty,
      );
    });
  });

  test('DATA_DIR defaults to ./data', () {
    expect(ServerEnvironment.dataDir({}), 'data');
    expect(
      ServerEnvironment.dataDir({'DATA_DIR': ' /var/lib/raen '}),
      '/var/lib/raen',
    );
  });
}
