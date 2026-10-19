import 'package:web_socket_channel/io.dart';

import 'realtime_socket.dart';
import 'realtime_socket_channel.dart';

/// Android/iOS/desktop: `IOWebSocketChannel` con **ping WebSocket nativo**
/// ([realtimePingInterval]) — senza, un socket mezzo aperto (telefono che
/// passa dal Wi-Fi al 4G, ascensore) resterebbe "connesso" per minuti senza
/// che nessuno se ne accorga — e con un timeout sulla connessione.
RealtimeSocket connectRealtimeSocket(Uri uri) => RealtimeSocketChannel(
  IOWebSocketChannel.connect(
    uri,
    pingInterval: realtimePingInterval,
    connectTimeout: const Duration(seconds: 10),
  ),
);

/// Stesso intervallo del ping del server (`server/routes/ws.dart`).
const realtimePingInterval = Duration(seconds: 20);
