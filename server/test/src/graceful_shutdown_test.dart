import 'dart:async';

import 'package:test/test.dart';
import 'package:threemojo_server/src/graceful_shutdown.dart';
import 'package:threemojo_server/src/log.dart';

void main() {
  setUp(() => Log.sink = (_) {});

  test('stops accepting, tells the clients, flushes, then exits 0 — in '
      'order', () async {
    final events = <String>[];
    int? exitCode;
    final shutdown = GracefulShutdown(
      stopAccepting: () async => events.add('stopAccepting'),
      closeClients: () => events.add('closeClients'),
      flushers: [
        () async => events.add('flushA'),
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          events.add('flushB');
        },
      ],
      drainDelay: Duration.zero,
      exit: (code) => exitCode = code,
    );

    await shutdown.run('SIGTERM');

    expect(events.take(2), ['stopAccepting', 'closeClients']);
    expect(events, containsAll(['flushA', 'flushB']));
    expect(exitCode, 0);
  });

  test('a second signal does nothing', () async {
    var closes = 0;
    var exits = 0;
    final shutdown = GracefulShutdown(
      stopAccepting: () async {},
      closeClients: () => closes++,
      drainDelay: Duration.zero,
      exit: (_) => exits++,
    );
    await Future.wait([shutdown.run('SIGTERM'), shutdown.run('SIGINT')]);
    await shutdown.run('SIGTERM');
    expect(closes, 1);
    expect(exits, 1);
  });

  test('a flush that fails does not block the exit', () async {
    int? exitCode;
    final shutdown = GracefulShutdown(
      stopAccepting: () async {},
      closeClients: () {},
      flushers: [() async => throw StateError('disk')],
      drainDelay: Duration.zero,
      exit: (code) => exitCode = code,
    );
    await shutdown.run('SIGTERM');
    expect(exitCode, 0);
  });

  test(
    'something that never answers is cut at the deadline (exit 1)',
    () async {
      final exits = <int>[];
      final never = Completer<void>();
      final shutdown = GracefulShutdown(
        stopAccepting: () async {},
        closeClients: () {},
        flushers: [() => never.future],
        deadline: const Duration(milliseconds: 50),
        drainDelay: Duration.zero,
        exit: exits.add,
      );
      unawaited(shutdown.run('SIGTERM'));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(exits, [1]);
    },
  );
}
