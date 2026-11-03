import 'package:test/test.dart';
import 'package:threemojo_server/src/paywall_mode.dart';

void main() {
  group('PaywallConfig.fromEnvironment', () {
    test('without PAYWALL_MODE it is the paid paywall, with no warning', () {
      final config = PaywallConfig.fromEnvironment({});

      expect(config.mode, PaywallMode.paid);
      expect(config.problem, isNull);
    });

    test('paid and free are read, whatever the case or the spaces', () {
      expect(
        PaywallConfig.fromEnvironment({'PAYWALL_MODE': 'paid'}).mode,
        PaywallMode.paid,
      );
      expect(
        PaywallConfig.fromEnvironment({'PAYWALL_MODE': ' FREE '}).mode,
        PaywallMode.free,
      );
    });

    test('a typo never makes everything free: paid, with a warning', () {
      final config = PaywallConfig.fromEnvironment({'PAYWALL_MODE': 'fre'});

      expect(config.mode, PaywallMode.paid);
      expect(config.problem, contains('PAYWALL_MODE="fre"'));
    });
  });
}
