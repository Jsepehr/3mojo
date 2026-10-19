import 'package:test/test.dart';
import 'package:threemojo_server/src/client_ip.dart';

void main() {
  group('resolveClientIp', () {
    test('without trusted proxies X-Forwarded-For is ignored', () {
      expect(
        resolveClientIp(
          remoteAddress: '203.0.113.7',
          forwardedFor: '1.2.3.4',
          trustedProxies: const {},
        ),
        '203.0.113.7',
      );
    });

    test('from a trusted proxy, the last hop that is not a proxy wins', () {
      expect(
        resolveClientIp(
          remoteAddress: '10.0.0.2',
          // The client wrote "6.6.6.6" itself: only the hops appended by
          // our proxies are trustworthy.
          forwardedFor: '6.6.6.6, 198.51.100.9, 10.0.0.3',
          trustedProxies: const {'10.0.0.2', '10.0.0.3'},
        ),
        '198.51.100.9',
      );
    });

    test('from a trusted proxy without the header, the proxy address', () {
      expect(
        resolveClientIp(
          remoteAddress: '10.0.0.2',
          forwardedFor: null,
          trustedProxies: const {'10.0.0.2'},
        ),
        '10.0.0.2',
      );
    });

    test('reads TRUSTED_PROXY as a comma separated list', () {
      expect(
        trustedProxiesFromEnvironment({'TRUSTED_PROXY': ' 127.0.0.1, ::1 ,'}),
        {'127.0.0.1', '::1'},
      );
      expect(trustedProxiesFromEnvironment({}), isEmpty);
    });
  });
}
