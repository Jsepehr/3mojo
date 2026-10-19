import 'package:web_socket_channel/web_socket_channel.dart';

import 'realtime_socket.dart';

/// [RealtimeSocket] sopra un `WebSocketChannel` vero (qualsiasi piattaforma).
class RealtimeSocketChannel implements RealtimeSocket {
  RealtimeSocketChannel(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  Future<void> get ready => _channel.ready;

  @override
  int? get closeCode => _channel.closeCode;

  @override
  void add(String data) => _channel.sink.add(data);

  @override
  Future<void> close([int? closeCode]) => _channel.sink.close(closeCode);
}
