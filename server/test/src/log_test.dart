import 'dart:convert';

import 'package:test/test.dart';
import 'package:threemojo_server/src/log.dart';

void main() {
  late List<Map<String, dynamic>> lines;
  late void Function(String) originalSink;
  late LogLevel originalLevel;

  setUp(() {
    lines = [];
    originalSink = Log.sink;
    originalLevel = Log.minimumLevel;
    Log.minimumLevel = LogLevel.debug;
    Log.clock = () => DateTime.utc(2026, 11, 2, 8, 30, 15);
    Log.sink = (line) => lines.add(jsonDecode(line) as Map<String, dynamic>);
  });

  tearDown(() {
    Log.sink = originalSink;
    Log.minimumLevel = originalLevel;
    Log.clock = DateTime.now;
  });

  test('one JSON line per event with time, level and event', () {
    Log.info('payments.mode', {'mode': 'real', 'ios': true, 'n': 3});

    expect(lines.single, {
      't': '2026-11-02T08:30:15.000Z',
      'level': 'info',
      'event': 'payments.mode',
      'mode': 'real',
      'ios': true,
      'n': 3,
    });
  });

  test('IPs and tokens never get through, whatever the caller passes', () {
    Log.warn('x', {
      'a': 'client 203.0.113.7 said hi',
      'b': 'from 2001:db8::1 and ::ffff:10.0.0.1',
      'c': 'token ${'f' * 32} and ${'Ab1_' * 10}',
      'd': 'ok text',
    });

    final line = jsonEncode(lines.single);
    expect(line, isNot(contains('203.0.113.7')));
    expect(line, isNot(contains('2001:db8')));
    expect(line, isNot(contains('10.0.0.1')));
    expect(line, isNot(contains('f' * 24)));
    expect(line, isNot(contains('Ab1_Ab1_Ab1_Ab1_')));
    expect(lines.single['d'], 'ok text');
  });

  test('an error is reduced to its type, never its message', () {
    try {
      jsonDecode('{"secret": "abcdefghijklmnopqrstuvwxyz0123"');
    } catch (error, stack) {
      Log.error('ws.message_unhandled', error: error, stackTrace: stack);
    }

    final line = lines.single;
    expect(line['level'], 'error');
    expect(line['errorType'], 'FormatException');
    expect(jsonEncode(line), isNot(contains('abcdefghijklmnop')));
    expect(line['stack'], isA<List>());
    expect(
      (line['stack'] as List).length,
      lessThanOrEqualTo(Log.maxStackFrames),
    );
  });

  test('long values are cut, levels below the minimum are skipped', () {
    Log.info('x', {'long': 'a b ' * 200});
    expect((lines.single['long'] as String).length, lessThan(300));

    lines.clear();
    Log.minimumLevel = LogLevel.warn;
    Log.info('quiet');
    Log.debug('quiet');
    expect(lines, isEmpty);
    Log.warn('loud');
    expect(lines, hasLength(1));
  });

  test('LOG_LEVEL is read from the environment', () {
    expect(Log.levelFromEnvironment({'LOG_LEVEL': 'ERROR'}), LogLevel.error);
    expect(Log.levelFromEnvironment({'LOG_LEVEL': 'nope'}), LogLevel.info);
    expect(Log.levelFromEnvironment({}), LogLevel.info);
  });

  test('a failing sink never throws into the server', () {
    Log.sink = (_) => throw StateError('stderr closed');
    expect(() => Log.info('x'), returnsNormally);
  });
}
