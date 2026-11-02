import 'package:test/test.dart';
import 'package:threemojo_server/src/client_ip.dart';
import 'package:threemojo_server/src/ip_address.dart';

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

  group('IPv4-mapped IPv6', () {
    test('normalizeIp maps ::ffff:a.b.c.d (both spellings) to IPv4', () {
      expect(normalizeIp('::ffff:127.0.0.1'), '127.0.0.1');
      expect(normalizeIp('::ffff:7f00:1'), '127.0.0.1');
      expect(normalizeIp('::FFFF:203.0.113.7'), '203.0.113.7');
      expect(normalizeIp('203.0.113.7'), '203.0.113.7');
      expect(normalizeIp('2001:db8::1'), '2001:db8::1');
      expect(normalizeIp('not an ip'), 'not an ip');
    });

    test('isLoopbackIp covers every loopback form', () {
      expect(isLoopbackIp('127.0.0.1'), isTrue);
      expect(isLoopbackIp('::ffff:127.0.0.1'), isTrue);
      expect(isLoopbackIp('::1'), isTrue);
      expect(isLoopbackIp('::ffff:10.0.0.1'), isFalse);
      expect(isLoopbackIp('garbage'), isFalse);
    });

    test('a mapped remote address matches a plain TRUSTED_PROXY entry', () {
      expect(
        resolveClientIp(
          remoteAddress: '::ffff:127.0.0.1',
          forwardedFor: '198.51.100.9',
          trustedProxies: const {'127.0.0.1'},
        ),
        '198.51.100.9',
      );
    });

    test('a plain remote address matches a mapped TRUSTED_PROXY entry', () {
      expect(
        resolveClientIp(
          remoteAddress: '127.0.0.1',
          forwardedFor: '198.51.100.9',
          trustedProxies: trustedProxiesFromEnvironment({
            'TRUSTED_PROXY': '::ffff:127.0.0.1',
          }),
        ),
        '198.51.100.9',
      );
    });

    test('mapped hops are normalized: same client, same rate-limit key', () {
      expect(
        resolveClientIp(
          remoteAddress: '127.0.0.1',
          forwardedFor: '::ffff:198.51.100.9, ::ffff:127.0.0.1',
          trustedProxies: const {'127.0.0.1'},
        ),
        '198.51.100.9',
      );
      expect(
        resolveClientIp(
          remoteAddress: '::ffff:203.0.113.7',
          forwardedFor: null,
          trustedProxies: const {},
        ),
        '203.0.113.7',
      );
    });
  });
}
