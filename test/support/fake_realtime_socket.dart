import 'dart:async';
import 'dart:convert';

import 'package:threemojo_app/core/network/realtime_connection.dart';
import 'package:threemojo_app/core/network/realtime_socket.dart';
import 'package:threemojo_app/core/network/reconnect_backoff.dart';

/// Un socket finto: il test fa da server (manda frame con [serverSends],
/// legge cosa ha mandato il client in [sent], chiude con [serverCloses]).
class FakeRealtimeSocket implements RealtimeSocket {
  FakeRealtimeSocket({bool connects = true}) {
    if (connects) {
      _ready.complete();
    } else {
      _ready.completeError(StateError('unreachable'));
      _ready.future.ignore();
      scheduleMicrotask(() {
        _incoming.addError(StateError('unreachable'));
        _incoming.close();
      });
    }
  }

  final _incoming = StreamController<dynamic>();
  final _ready = Completer<void>();
  final sent = <Map<String, dynamic>>[];
  bool closedByClient = false;

  @override
  int? closeCode;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  Future<void> get ready => _ready.future;

  @override
  void add(String data) {
    if (closedByClient) throw StateError('closed');
    sent.add(jsonDecode(data) as Map<String, dynamic>);
  }

  /// Come un vero socket, il client chiede la chiusura ma lo stream in
  /// arrivo finisce quando il server conferma ([serverCloses]); qui la
  /// conferma arriva al giro dopo.
  @override
  Future<void> close([int? closeCode]) async {
    closedByClient = true;
    scheduleMicrotask(() {
      if (!_incoming.isClosed) _incoming.close();
    });
  }

  void serverSends(Map<String, dynamic> message) {
    if (!_incoming.isClosed) _incoming.add(jsonEncode(message));
  }

  void welcome({bool resumed = false}) =>
      serverSends({'type': 'welcome', 'resumed': resumed, 'graceSeconds': 45});

  Future<void> serverCloses({int? code}) async {
    closeCode = code;
    if (!_incoming.isClosed) await _incoming.close();
  }

  Iterable<String?> get sentTypes => sent.map((m) => m['type'] as String?);
}

/// Una `RealtimeConnection` che apre solo socket finti (uno nuovo a ogni
/// tentativo) e riprova subito, senza attese.
class FakeRealtimeServer {
  FakeRealtimeServer() {
    connection = RealtimeConnection(
      socketFactory: (uri) {
        uris.add(uri);
        final socket = nextSocketConnects
            ? FakeRealtimeSocket()
            : FakeRealtimeSocket(connects: false);
        sockets.add(socket);
        return socket;
      },
      backoff: ReconnectBackoff(initial: Duration.zero, max: Duration.zero),
      endpoint: () => Uri.parse('ws://test/ws'),
    );
  }

  late final RealtimeConnection connection;
  final sockets = <FakeRealtimeSocket>[];
  final uris = <Uri>[];
  bool nextSocketConnects = true;

  FakeRealtimeSocket get last => sockets.last;
}

Future<void> pumpEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 5));
