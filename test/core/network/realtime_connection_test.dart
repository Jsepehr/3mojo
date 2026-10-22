import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/errors/exceptions.dart';
import 'package:threemojo_app/core/network/realtime_connection.dart';
import 'package:threemojo_app/core/network/reconnect_backoff.dart';

import '../../support/fake_realtime_socket.dart';

const _secret = '0f6a2c7e-1d3b-4c55-9a8e-7b2f4e6d8c10';
const _otherSecret = '9b1e5d3c-7a2f-4e60-8c4d-2f6a8b0c1e3d';

void main() {
  late FakeRealtimeServer server;

  setUp(() => server = FakeRealtimeServer());
  tearDown(() => server.connection.disconnect());

  test('the secret travels in the first message, never in the URL', () async {
    server.connection.connect(_secret);
    await pumpEvents();

    expect(server.uris.single.query, isEmpty);
    expect(server.last.sent.first, {'type': 'hello', 'secret': _secret});
  });

  test('send is refused until the server says welcome', () async {
    server.connection.connect(_secret);
    await pumpEvents();

    expect(server.connection.send({'type': 'ping'}), isFalse);

    server.last.welcome();
    await pumpEvents();

    expect(server.connection.isReady, isTrue);
    expect(server.connection.status, RealtimeStatus.online);
    expect(server.connection.send({'type': 'ping'}), isTrue);
    expect(server.last.sentTypes, ['hello', 'ping']);
  });

  test('a drop reports an error but keeps the stream open, reconnects by '
      'itself and says hello again', () async {
    final events = <Object>[];
    var done = false;
    server.connection
        .connect(_secret)
        .listen(events.add, onError: events.add, onDone: () => done = true);
    final ready = <bool>[];
    server.connection.onReady.listen(ready.add);
    await pumpEvents();
    server.last.welcome();
    await pumpEvents();

    await server.last.serverCloses();
    await pumpEvents();

    expect(events.whereType<ServerException>(), hasLength(1));
    expect(done, isFalse);
    expect(server.sockets, hasLength(2));
    expect(server.last.sent.first['type'], 'hello');

    server.last.welcome(resumed: true);
    await pumpEvents();
    expect(ready, [false, true]);
    expect(server.connection.status, RealtimeStatus.online);
  });

  test('a session closed by the server (sessionClosed) is announced and '
      'never reconnected: that would be a new Start', () async {
    final events = <Object>[];
    server.connection.connect(_secret).listen(events.add, onError: events.add);
    var closures = 0;
    server.connection.sessionClosures.listen((_) => closures++);
    await pumpEvents();
    server.last.welcome();
    await pumpEvents();

    server.last.serverSends({'type': 'sessionClosed', 'reason': 'reports'});
    await server.last.serverCloses(code: 4010);
    await pumpEvents();

    expect(closures, 1);
    expect(server.sockets, hasLength(1));
    expect(events.whereType<ServerException>(), isEmpty);
    expect(server.connection.status, RealtimeStatus.offline);

    // Nemmeno "Riprova" o il ritorno in primo piano la riaprono.
    server.connection
      ..connect(_secret)
      ..checkAlive();
    await pumpEvents();
    expect(server.sockets, hasLength(1));
  });

  test('keeps retrying while the server is unreachable', () async {
    server.nextSocketConnects = false;
    server.connection.connect(_secret);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(server.sockets.length, greaterThan(2));
    expect(server.connection.status, RealtimeStatus.reconnecting);
    expect(server.connection.send({'type': 'ping'}), isFalse);
  });

  test('the same session reuses the same stream and socket', () async {
    final first = server.connection.connect(_secret);
    final second = server.connection.connect(_secret);

    expect(first, equals(second));
    expect(server.sockets, hasLength(1));
  });

  test('another session closes the previous channel, saying end', () async {
    var firstDone = false;
    server.connection
        .connect(_secret)
        .listen((_) {}, onDone: () => firstDone = true);
    await pumpEvents();
    final firstSocket = server.last..welcome();
    await pumpEvents();

    server.connection.connect(_otherSecret);
    await pumpEvents();

    expect(firstSocket.sentTypes, contains('end'));
    expect(firstSocket.closedByClient, isTrue);
    expect(firstDone, isTrue);
    expect(server.last.sent.first, {'type': 'hello', 'secret': _otherSecret});
  });

  test(
    'disconnect says end, closes the stream and stops reconnecting',
    () async {
      var done = false;
      server.connection
          .connect(_secret)
          .listen((_) {}, onDone: () => done = true);
      await pumpEvents();
      final socket = server.last..welcome();
      await pumpEvents();

      await server.connection.disconnect();
      await pumpEvents();

      expect(socket.sentTypes.last, 'end');
      expect(socket.closedByClient, isTrue);
      expect(done, isTrue);
      expect(server.sockets, hasLength(1));
      expect(server.connection.status, RealtimeStatus.offline);
      expect(server.connection.send({'type': 'ping'}), isFalse);
    },
  );

  test('a frame arriving while the old socket is still closing is ignored, '
      'not added to a closed stream', () async {
    final events = <Object>[];
    server.connection.connect(_secret).listen(events.add, onError: events.add);
    await pumpEvents();
    final socket = server.last..welcome();
    await pumpEvents();
    events.clear();

    final closing = server.connection.disconnect();
    socket.serverSends({'type': 'nearby', 'people': []});
    await closing;
    await pumpEvents();

    expect(events, isEmpty);
    expect(server.connection.isReady, isFalse);
  });

  group('checkAlive (back to the foreground)', () {
    test('a socket that does not answer the ping is dropped and replaced '
        'right away, without saying end', () {
      fakeAsync((async) {
        final fake = FakeRealtimeServer();
        fake.connection.connect(_secret).listen((_) {}, onError: (_) {});
        async.flushMicrotasks();
        final dead = fake.last..welcome();
        async.flushMicrotasks();

        fake.connection.checkAlive();
        expect(dead.sentTypes.last, 'ping');
        async.elapse(fake.connection.probeTimeout);

        expect(dead.closedByClient, isTrue);
        expect(dead.sentTypes, isNot(contains('end')));
        expect(fake.sockets, hasLength(2));
        expect(fake.last.sent.first, {'type': 'hello', 'secret': _secret});
        expect(fake.connection.status, RealtimeStatus.reconnecting);

        fake.connection.disconnect();
        async.flushMicrotasks();
      });
    });

    test('a socket that answers (pong) is kept', () {
      fakeAsync((async) {
        final fake = FakeRealtimeServer();
        fake.connection.connect(_secret).listen((_) {}, onError: (_) {});
        async.flushMicrotasks();
        final alive = fake.last..welcome();
        async.flushMicrotasks();

        fake.connection.checkAlive();
        alive.serverSends({'type': 'pong'});
        async.flushMicrotasks();
        async.elapse(fake.connection.probeTimeout * 2);

        expect(alive.closedByClient, isFalse);
        expect(fake.sockets, hasLength(1));
        expect(fake.connection.status, RealtimeStatus.online);

        fake.connection.disconnect();
        async.flushMicrotasks();
      });
    });

    test('while waiting for the next retry it tries again immediately', () {
      fakeAsync((async) {
        final sockets = <FakeRealtimeSocket>[];
        final connection = RealtimeConnection(
          socketFactory: (_) {
            final socket = FakeRealtimeSocket();
            sockets.add(socket);
            return socket;
          },
          backoff: ReconnectBackoff(
            initial: const Duration(minutes: 1),
            max: const Duration(minutes: 1),
          ),
          endpoint: () => Uri.parse('ws://test/ws'),
        );
        connection.connect(_secret).listen((_) {}, onError: (_) {});
        async.flushMicrotasks();
        sockets.last.welcome();
        async.flushMicrotasks();
        sockets.last.serverCloses();
        async.flushMicrotasks();
        expect(sockets, hasLength(1));

        connection.checkAlive();
        async.flushMicrotasks();

        expect(sockets, hasLength(2));
        connection.disconnect();
        async.flushMicrotasks();
      });
    });

    test('without a session it does nothing', () {
      server.connection.checkAlive();
      expect(server.sockets, isEmpty);
    });
  });

  group('End while reconnecting', () {
    RealtimeConnection slowRetries(List<FakeRealtimeSocket> sockets) =>
        RealtimeConnection(
          socketFactory: (_) {
            final socket = FakeRealtimeSocket();
            sockets.add(socket);
            return socket;
          },
          backoff: ReconnectBackoff(
            initial: const Duration(minutes: 5),
            max: const Duration(minutes: 5),
          ),
          endpoint: () => Uri.parse('ws://test/ws'),
        );

    test('within the server grace, end still reaches the server on a '
        'farewell socket as soon as it is ready', () {
      fakeAsync((async) {
        final sockets = <FakeRealtimeSocket>[];
        final connection = slowRetries(sockets);
        connection.connect(_secret).listen((_) {}, onError: (_) {});
        async.flushMicrotasks();
        sockets.last.welcome();
        async.flushMicrotasks();
        sockets.last.serverCloses();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));

        connection.disconnect();
        async.flushMicrotasks();

        expect(sockets, hasLength(2));
        final farewell = sockets.last;
        expect(farewell.sent.single, {'type': 'hello', 'secret': _secret});
        expect(connection.status, RealtimeStatus.offline);

        farewell.welcome(resumed: true);
        async.flushMicrotasks();

        expect(farewell.sentTypes, ['hello', 'end']);
        expect(farewell.closedByClient, isTrue);
        // Nessun altro tentativo: la connessione resta chiusa.
        async.elapse(const Duration(minutes: 10));
        expect(sockets, hasLength(2));
      });
    });

    test('after the server grace there is nothing to end: no farewell', () {
      fakeAsync((async) {
        final sockets = <FakeRealtimeSocket>[];
        final connection = slowRetries(sockets);
        connection.connect(_secret).listen((_) {}, onError: (_) {});
        async.flushMicrotasks();
        sockets.last.welcome();
        async.flushMicrotasks();
        sockets.last.serverCloses();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 46));

        connection.disconnect();
        async.flushMicrotasks();

        expect(sockets, hasLength(1));
      });
    });

    test('a farewell that never gets a welcome gives up on its own', () {
      fakeAsync((async) {
        final sockets = <FakeRealtimeSocket>[];
        final connection = slowRetries(sockets);
        connection.connect(_secret).listen((_) {}, onError: (_) {});
        async.flushMicrotasks();
        sockets.last.welcome();
        async.flushMicrotasks();
        sockets.last.serverCloses();
        async.flushMicrotasks();

        connection.disconnect();
        async.flushMicrotasks();
        async.elapse(connection.farewellTimeout);

        expect(sockets.last.closedByClient, isTrue);
        expect(sockets.last.sentTypes, isNot(contains('end')));
      });
    });
  });
}
