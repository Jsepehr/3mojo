import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Simula 20 dispositivi finti che parlano con il server **vero** (`server/`
/// acceso e raggiungibile) tramite lo stesso WebSocket che userebbe l'app —
/// serve a provare hotspot/vicinanze con più "telefoni" senza bisogno di
/// dispositivi reali sulla stessa rete Wi-Fi: ognuno è solo una connessione
/// WebSocket in più aperta da questo processo.
///
/// Uso: `dart run tool/simulate_fake_devices.dart [wsBaseUrl]`
/// (default `ws://localhost:8080`, lo stesso host/porta di `dart_frog dev`).
/// Il server deve già essere acceso in un altro terminale.
///
/// Disposizione dei 20 dispositivi (vedi [_seedDevices]):
/// - **Gruppo A** (`a1`..`a4` nucleo stretto, `a5` sul bordo): i primi 4 sono
///   entro ~30m l'uno dall'altro, quindi si vedono già tra loro fin da
///   subito con la regola normale (100m) — dopo 15 minuti reali di
///   permanenza qui dovrebbe formarsi un hotspot (vedi `HotspotStore` in
///   `lib/src/hotspot_store.dart`). `a5` è invece a ~150m dal nucleo:
///   **troppo lontano per vederli con la regola normale**, ma abbastanza
///   vicino da rientrare nei 200m dell'hotspot una volta formato — è lui il
///   dispositivo da guardare per vedere l'effetto vero dell'hotspot
///   (visibilità che compare dal nulla dopo 15 minuti, non solo "un hotspot
///   esiste").
/// - **Gruppo B** (`b1`..`b5`, stessa forma nucleo+bordo): identico al
///   Gruppo A, ma ~600m più a nord — abbastanza lontano da non far
///   sovrapporre i due hotspot (serve ≥400m tra i centri), abbastanza
///   vicino da vedere sullo schermo due zone indipendenti formarsi in
///   parallelo.
/// - **Coppie isolate** (`p1a`/`p1b` .. `p5a`/`p5b`, 10 dispositivi): 5 coppie,
///   ognuna entro il raggio base (100m) tra i due membri ma a >2km dalle
///   altre coppie e dai due gruppi — mai abbastanza gente vicina per un
///   hotspot (solo 2 persone, sotto il minimo di 3), solo la visibilità
///   normale a due, visibile fin dal primo minuto.
///
/// Ogni dispositivo rimanda la sua posizione ogni [_presenceInterval] (ben
/// sotto i 90s di `SessionStore.purgeStale`, così nessuno sparisce da solo)
/// e stampa la propria lista "vicinanze" ogni volta che cambia composizione,
/// più un conto alla rovescia periodico verso i 15 minuti che servono per un
/// hotspot -- utile per non dover controllare un cronometro a parte.
Future<void> main(List<String> args) async {
  final wsBaseUrl = args.isNotEmpty ? args.first : 'ws://localhost:8080';
  final startedAt = DateTime.now();

  stdout.writeln('Simulazione di 20 dispositivi finti verso $wsBaseUrl/ws');
  stdout.writeln(
    'Un hotspot nel Gruppo A/B richiede 15 minuti reali di permanenza '
    'e dura 1 ora -- lascia girare questo processo, non serve fare altro.',
  );
  stdout.writeln('Ctrl+C per fermare tutto in modo pulito.\n');

  final devices = _seedDevices();
  final clients = <_FakeDevice>[];

  for (final device in devices) {
    final client = await _FakeDevice.connect(device, wsBaseUrl, startedAt);
    clients.add(client);
  }

  final statusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
    final elapsed = DateTime.now().difference(startedAt);
    stdout.writeln(
      '\n--- ${_formatDuration(elapsed)} dalla partenza '
      '(hotspot a 15:00, se il gruppo tiene) ---',
    );
  });

  late final StreamSubscription<ProcessSignal> sigintSubscription;
  final done = Completer<void>();
  sigintSubscription = ProcessSignal.sigint.watch().listen((_) {
    done.complete();
  });

  await done.future;
  statusTimer.cancel();
  await sigintSubscription.cancel();
  stdout.writeln('\nChiusura di tutte le connessioni finte...');
  for (final client in clients) {
    await client.close();
  }
  exit(0);
}

class _DeviceSeed {
  const _DeviceSeed(this.id, this.lat, this.lng, this.gender);

  final String id;
  final double lat;
  final double lng;
  final String gender;
}

/// ~111320m per grado di latitudine -- stessa approssimazione grossolana
/// usata in `HotspotStore` per il partizionamento spaziale, qui serve solo a
/// piazzare i dispositivi finti a una distanza approssimativa voluta.
const _metersPerDegreeLat = 111320.0;

double _latOffset(double meters) => meters / _metersPerDegreeLat;

List<_DeviceSeed> _seedDevices() {
  const originLat = 45.4642; // Milano, punto di riferimento arbitrario.
  const originLng = 9.1900;

  final devices = <_DeviceSeed>[];

  // Nucleo stretto (entro ~30m) + un dispositivo di bordo a ~150m -- troppo
  // lontano dal nucleo per la regola normale (100m), ma dentro ai 200m
  // dell'hotspot una volta formato: è quello che mostra l'effetto vero.
  final coreOffsets = [(0.0, 0.0), (8.0, 0.0), (0.0, 8.0), (-8.0, 6.0)];
  const edgeOffset = (150.0, 0.0);

  void addGroup(String prefix, double latShift) {
    for (var i = 0; i < coreOffsets.length; i++) {
      final (dLat, dLng) = coreOffsets[i];
      devices.add(
        _DeviceSeed(
          '$prefix${i + 1}',
          originLat + _latOffset(latShift + dLat),
          originLng + _latOffset(dLng),
          i.isEven ? 'male' : 'female',
        ),
      );
    }
    final (edgeLat, edgeLng) = edgeOffset;
    devices.add(
      _DeviceSeed(
        '${prefix}5',
        originLat + _latOffset(latShift + edgeLat),
        originLng + _latOffset(edgeLng),
        'male',
      ),
    );
  }

  addGroup('a', 0.0);
  // Gruppo B ~600m più a nord del Gruppo A -- abbastanza lontano da non far
  // sovrapporre i due hotspot (serve >=400m tra i centri), vicino abbastanza
  // da vedere due zone indipendenti formarsi in parallelo.
  addGroup('b', 600.0);

  // 5 coppie isolate, ognuna a >2km dalle altre e dai due gruppi -- mai
  // abbastanza gente vicina per un hotspot, solo visibilità normale a due.
  for (var i = 0; i < 5; i++) {
    final pairLatShift = -2000.0 * (i + 1);
    devices.add(
      _DeviceSeed(
        'p${i + 1}a',
        originLat + _latOffset(pairLatShift),
        originLng,
        'male',
      ),
    );
    devices.add(
      _DeviceSeed(
        'p${i + 1}b',
        originLat + _latOffset(pairLatShift + 20),
        originLng,
        'female',
      ),
    );
  }

  return devices;
}

class _FakeDevice {
  _FakeDevice(this.seed, this._channel, this._startedAt) {
    _sendPresence();
    _resendTimer = Timer.periodic(_presenceInterval, (_) => _sendPresence());
    _subscription = _channel.stream.listen(_onMessage);
  }

  static const _presenceInterval = Duration(seconds: 20);

  final _DeviceSeed seed;
  final WebSocketChannel _channel;
  final DateTime _startedAt;
  late final Timer _resendTimer;
  late final StreamSubscription<dynamic> _subscription;
  List<String> _lastNearbyIds = const [];

  static Future<_FakeDevice> connect(
    _DeviceSeed seed,
    String wsBaseUrl,
    DateTime startedAt,
  ) async {
    final uri = Uri.parse('$wsBaseUrl/ws?sessionId=${seed.id}');
    final channel = IOWebSocketChannel.connect(uri);
    await channel.ready;
    stdout.writeln('[00:00] ${seed.id} connesso (vede ancora nessuno)');
    return _FakeDevice(seed, channel, startedAt);
  }

  void _sendPresence() {
    _channel.sink.add(
      jsonEncode({
        'type': 'presence',
        'lat': seed.lat,
        'lng': seed.lng,
        'gender': seed.gender,
        'genderPreference': 'everyone',
        'selfieBase64': '',
      }),
    );
  }

  void _onMessage(dynamic raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw as String);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic> || decoded['type'] != 'nearby') {
      return;
    }

    final people = (decoded['people'] as List).cast<Map<String, dynamic>>();
    final ids = people.map((p) => p['sessionId'] as String).toList()..sort();
    if (ids.length == _lastNearbyIds.length &&
        ids.join(',') == _lastNearbyIds.join(',')) {
      return;
    }
    _lastNearbyIds = ids;

    final dwell = _formatDuration(DateTime.now().difference(_startedAt));
    stdout.writeln(
      '[$dwell] ${seed.id} ora vede ${ids.length} persone: '
      '${ids.isEmpty ? "(nessuna)" : ids.join(", ")}',
    );
  }

  Future<void> close() async {
    _resendTimer.cancel();
    await _subscription.cancel();
    await _channel.sink.close();
  }
}

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}
