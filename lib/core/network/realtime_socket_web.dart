import 'package:web_socket_channel/web_socket_channel.dart';

import 'realtime_socket.dart';
import 'realtime_socket_channel.dart';

/// Web: il browser non espone il ping WebSocket, quindi nessun ping nativo
/// qui — ci pensa il `ping` applicativo di `RealtimeConnection`, che vale su
/// tutte le piattaforme.
RealtimeSocket connectRealtimeSocket(Uri uri) =>
    RealtimeSocketChannel(WebSocketChannel.connect(uri));
