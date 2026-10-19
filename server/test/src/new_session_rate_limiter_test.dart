import 'package:test/test.dart';
import 'package:threemojo_server/src/new_session_rate_limiter.dart';
import 'package:threemojo_server/src/rate_limiters.dart';

void main() {
  group('NewSessionRateLimiter', () {
    late DateTime clock;
    late NewSessionRateLimiter limiter;

    setUp(() {
      clock = DateTime(2026, 1, 1);
      limiter = NewSessionRateLimiter.withClock(() => clock);
    });

    test('allows up to the limit per IP within the window, then refuses', () {
      for (var i = 0; i < NewSessionRateLimiter.maxNewSessions; i++) {
        expect(limiter.tryStart('1.2.3.4'), isTrue);
      }
      expect(limiter.tryStart('1.2.3.4'), isFalse);
    });

    test('other IPs are not affected', () {
      for (var i = 0; i < NewSessionRateLimiter.maxNewSessions; i++) {
        limiter.tryStart('1.2.3.4');
      }
      expect(limiter.tryStart('5.6.7.8'), isTrue);
    });

    test('the limit can be changed from the environment, the default stays '
        'otherwise', () {
      const key = NewSessionRateLimiter.limitEnvironmentVariable;
      expect(NewSessionRateLimiter.limitFromEnvironment({}), 20);
      expect(NewSessionRateLimiter.limitFromEnvironment({key: '200'}), 200);
      expect(NewSessionRateLimiter.limitFromEnvironment({key: '0'}), 20);
      expect(NewSessionRateLimiter.limitFromEnvironment({key: 'tanti'}), 20);

      final relaxed = NewSessionRateLimiter.withClock(() => clock, limit: 30);
      for (var i = 0; i < 30; i++) {
        expect(relaxed.tryStart('1.2.3.4'), isTrue);
      }
      expect(relaxed.tryStart('1.2.3.4'), isFalse);
    });

    test('allows again once the window has passed', () {
      for (var i = 0; i < NewSessionRateLimiter.maxNewSessions; i++) {
        limiter.tryStart('1.2.3.4');
      }
      clock = clock.add(NewSessionRateLimiter.window);

      expect(limiter.tryStart('1.2.3.4'), isTrue);
    });
  });

  group('ConnectionRateLimiter', () {
    test('allows a burst, then refills over time', () {
      var clock = DateTime(2026, 1, 1);
      final limiter = ConnectionRateLimiter(
        burst: 3,
        refillPerSecond: 1,
        now: () => clock,
      );

      expect(
        [for (var i = 0; i < 4; i++) limiter.tryConsume()],
        [true, true, true, false],
      );

      clock = clock.add(const Duration(seconds: 2));
      expect(limiter.tryConsume(), isTrue);
      expect(limiter.tryConsume(), isTrue);
      expect(limiter.tryConsume(), isFalse);
    });
  });
}
