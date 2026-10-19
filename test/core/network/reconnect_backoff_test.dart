import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/network/reconnect_backoff.dart';

void main() {
  test('grows exponentially from 0.5s up to 30s, with jitter in the upper '
      'half', () {
    final backoff = ReconnectBackoff(random: Random(1));
    final delays = [for (var i = 0; i < 10; i++) backoff.next()];

    const nominalMs = [500, 1000, 2000, 4000, 8000, 16000, 30000, 30000];
    for (var i = 0; i < nominalMs.length; i++) {
      expect(delays[i].inMilliseconds, greaterThanOrEqualTo(nominalMs[i] ~/ 2));
      expect(delays[i].inMilliseconds, lessThanOrEqualTo(nominalMs[i]));
    }
  });

  test('reset starts again from the shortest wait, jumpToMax from the '
      'longest', () {
    final backoff = ReconnectBackoff(random: Random(2));
    for (var i = 0; i < 5; i++) {
      backoff.next();
    }

    backoff.reset();
    expect(backoff.next().inMilliseconds, lessThanOrEqualTo(500));

    backoff.jumpToMax();
    expect(backoff.next().inMilliseconds, greaterThanOrEqualTo(15000));
  });
}
