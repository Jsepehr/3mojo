import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/encounter_store.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/new_session_rate_limiter.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/pseudonyms.dart';
import 'package:threemojo_server/src/realtime_message_handler.dart';
import 'package:threemojo_server/src/session_credentials.dart';
import 'package:threemojo_server/src/session_lifecycle.dart';
import 'package:threemojo_server/src/session_store.dart';
import 'package:threemojo_server/src/socket_session.dart';

/// Tutto il server realtime con store indipendenti e orologio controllabile:
/// ogni `_Client` è un "socket" fatto di due `StreamController`.
class _World {
  _World() {
    sessions = SessionStore.withClock(() => clock);
    paywall = PaywallStore.withClock(() => clock);
    hotspots = HotspotStore.withClock(() => clock);
    hub = ConnectionHub.withStore(
      sessions,
      encounterStore: encounters,
      paywallStore: paywall,
      hotspotStore: hotspots,
      pseudonyms: pseudonyms,
      broadcastThrottleInterval: Duration.zero,
    );
    rateLimiter = NewSessionRateLimiter.withClock(() => clock);
    lifecycle = SessionLifecycle(
      sessions: sessions,
      encounters: encounters,
      hub: hub,
      credentials: credentials,
      rateLimiter: rateLimiter,
      gracePeriod: const Duration(milliseconds: 150),
      now: () => clock,
    );
    handler = RealtimeMessageHandler(
      sessions: sessions,
      encounters: encounters,
      hub: hub,
      paywall: paywall,
      hotspots: hotspots,
    );
  }

  DateTime clock = DateTime(2026, 1, 1);
  late final SessionStore sessions;
  final encounters = EncounterStore.empty();
  late final PaywallStore paywall;
  late final HotspotStore hotspots;
  final pseudonyms = Pseudonyms();
  late final ConnectionHub hub;
  final credentials = SessionCredentials.empty();
  late final NewSessionRateLimiter rateLimiter;
  late final SessionLifecycle lifecycle;
  late final RealtimeMessageHandler handler;

  _Client open({
    String ip = '10.0.0.1',
    Duration helloTimeout = const Duration(seconds: 5),
  }) {
    final client = _Client();
    SocketSession(
      incoming: client.toServer.stream,
      outgoing: client.fromServer,
      clientIp: ip,
      lifecycle: lifecycle,
      handler: handler,
      helloTimeout: helloTimeout,
    ).start();
    return client;
  }

  /// Apre un socket, saluta con [secret] e (se [lat] non è null) manda una
  /// presenza.
  Future<_Client> join(
    String secret, {
    double? lat = 0,
    double lng = 0,
    String ip = '10.0.0.1',
    String? unlockToken,
  }) async {
    final client = open(ip: ip)..hello(secret);
    if (lat != null) {
      client.presence(lat: lat, lng: lng, unlockToken: unlockToken);
    }
    await _settle();
    return client;
  }

  void dispose() {
    lifecycle.dispose();
    hub.stopHotspotDetection();
  }
}

class _Client {
  _Client() {
    fromServer.stream.listen(
      (raw) => messages.add(jsonDecode(raw as String) as Map<String, dynamic>),
      onDone: () {
        closedByServer = true;
        // Un vero socket chiuso dal server chiude anche lo stream in arrivo.
        unawaited(toServer.close());
      },
    );
  }

  final toServer = StreamController<dynamic>();
  final fromServer = StreamController<dynamic>();
  final messages = <Map<String, dynamic>>[];
  bool closedByServer = false;

  void send(Map<String, dynamic> message) => toServer.add(jsonEncode(message));

  void hello(String secret) => send({'type': 'hello', 'secret': secret});

  void presence({
    double lat = 0,
    double lng = 0,
    String? selfieBase64,
    String? unlockToken,
  }) => send({
    'type': 'presence',
    'lat': lat,
    'lng': lng,
    'selfieBase64': ?selfieBase64,
    'unlockToken': ?unlockToken,
  });

  /// La rete cade: il socket si chiude senza `end`.
  Future<void> dropConnection() => toServer.close();

  Map<String, dynamic>? last(String type) => messages
      .lastWhere((m) => m['type'] == type, orElse: () => {})
      .let((m) => m.isEmpty ? null : m);

  List<Map<String, dynamic>> nearby() =>
      ((last('nearby')?['people'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  String nearbyIdAt(int index) => nearby()[index]['personId'] as String;

  List<Map<String, dynamic>> encounters(String direction) =>
      ((last('encounters')?[direction] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  Map<String, dynamic>? rejected(String action) => messages
      .lastWhere(
        (m) => m['type'] == 'rejected' && m['action'] == action,
        orElse: () => {},
      )
      .let((m) => m.isEmpty ? null : m);
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

String _secret(String name) => '$name-secret'.padRight(36, 'x');

/// Un JPEG minimo strutturalmente valido (SOI, APP0, APP1/EXIF, SOS, EOI).
/// Il server non ne guarda i pixel, solo la struttura.
Uint8List _jpegWithExif() => Uint8List.fromList([
  0xFF, 0xD8, // SOI
  0xFF, 0xE0, 0x00, 0x07, 0x4A, 0x46, 0x49, 0x46, 0x00, // APP0 "JFIF\0"
  0xFF, 0xE1, 0x00, 0x08, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // APP1 "Exif"
  0xFF, 0xDA, 0x00, 0x04, 0x01, 0x02, // SOS
  0x11, 0x22, 0x33, // dati compressi
  0xFF, 0xD9, // EOI
]);

void main() {
  late _World world;

  setUp(() => world = _World());
  tearDown(() => world.dispose());

  /// A e B vicini, entrambi visibili l'uno all'altra.
  Future<(_Client, _Client)> twoNeighbours() async {
    final a = await world.join(_secret('a'));
    final b = await world.join(_secret('b'));
    world.clock = world.clock.add(const Duration(minutes: 5));
    world.hub.broadcastNearbyUpdates();
    await _settle();
    return (a, b);
  }

  /// A e B in match (A ha chiesto, B ha accettato).
  Future<(_Client, _Client)> matched() async {
    final (a, b) = await twoNeighbours();
    a.send({'type': 'sendEncounterRequest', 'toPersonId': a.nearbyIdAt(0)});
    await _settle();
    final requestId = b.encounters('incoming').single['id'];
    b.send({
      'type': 'respondToEncounterRequest',
      'requestId': requestId,
      'accepted': true,
    });
    await _settle();
    expect(a.encounters('outgoing').single['status'], 'accepted');
    return (a, b);
  }

  group('hello', () {
    test('a socket that never says hello is closed without registering '
        'anything', () async {
      final client = world.open(helloTimeout: const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(client.closedByServer, isTrue);
      expect(world.sessions.allSessions, isEmpty);
    });

    test('any other message before hello closes the socket', () async {
      final client = world.open()..presence();
      await _settle();

      expect(client.closedByServer, isTrue);
      expect(world.sessions.allSessions, isEmpty);
    });

    test('a short secret is refused', () async {
      final client = world.open()..hello('too-short');
      await _settle();

      expect(client.last('error')?['code'], 'invalidSecret');
      expect(client.closedByServer, isTrue);
    });

    test('a valid hello gets a welcome for a new session', () async {
      final client = world.open()..hello(_secret('a'));
      await _settle();

      expect(client.last('welcome'), {
        'type': 'welcome',
        'resumed': false,
        'graceSeconds': 0,
      });
    });
  });

  group('grace period', () {
    test('reconnecting within the grace keeps the same person, the dwell '
        'time and the match, and does not count as a new Start', () async {
      // Fill the per-IP Start limit, A and B included.
      final (a, b) = await matched();
      for (var i = 0; i < NewSessionRateLimiter.maxNewSessions - 2; i++) {
        await world.join(_secret('filler$i'), lat: null);
      }
      final aIdSeenByB = b.encounters('incoming').single['otherPersonId'];

      await a.dropConnection();
      await _settle();
      // Hidden while away, but nothing is lost yet.
      expect(b.nearby(), isEmpty);
      expect(b.encounters('incoming').single['status'], 'accepted');

      final a2 = await world.join(_secret('a'), lat: null);

      expect(a2.last('welcome')?['resumed'], isTrue);
      expect(a2.encounters('outgoing').single['status'], 'accepted');
      expect(b.nearby().single['personId'], aIdSeenByB);
      // Dwell time intact: still "high" right away.
      expect(b.nearby().single['meetingChance'], 'high');

      // The rate limiter was not touched by the reconnection: a genuinely
      // new session from the same IP is still refused.
      final newcomer = world.open()..hello(_secret('newcomer'));
      await _settle();
      expect(newcomer.last('error')?['code'], 'rateLimited');
    });

    test('when the grace expires the partner sees the match ended and the '
        'requests are forgotten', () async {
      final (a, b) = await matched();
      final aInternal = world.credentials.publicIdFor(_secret('a'));

      await a.dropConnection();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(b.encounters('incoming').single['status'], 'ended');
      expect(world.encounters.length, 0);
      expect(world.sessions.contains(aInternal), isFalse);

      // The same secret now starts a brand-new session.
      final a2 = await world.join(_secret('a'), lat: null);
      expect(a2.last('welcome')?['resumed'], isFalse);
      expect(a2.encounters('outgoing'), isEmpty);
    });

    test('an explicit end finishes the session right away', () async {
      final (a, b) = await matched();
      final aInternal = world.credentials.publicIdFor(_secret('a'));

      a.send({'type': 'end'});
      await _settle();

      expect(a.closedByServer, isTrue);
      expect(b.encounters('incoming').single['status'], 'ended');
      expect(b.nearby(), isEmpty);
      expect(world.lifecycle.isInGrace(aInternal), isFalse);
      expect(world.sessions.contains(aInternal), isFalse);
    });

    test('purging a silent session closes its socket and ends it', () async {
      final (a, b) = await matched();

      world.clock = world.clock.add(const Duration(seconds: 100));
      b.send({'type': 'ping'}); // B stays alive, A is silent.
      await _settle();
      final purged = world.lifecycle.purgeStale(const Duration(seconds: 90));
      await _settle();

      expect(purged, hasLength(1));
      expect(a.closedByServer, isTrue);
      expect(b.closedByServer, isFalse);
      expect(b.encounters('incoming').single['status'], 'ended');
    });
  });

  group('presence validation', () {
    test('a presence with Infinity coordinates is refused and does not stop '
        'the broadcast for anyone else', () async {
      final (a, b) = await twoNeighbours();

      // `1e400` decodes to Infinity.
      a.toServer.add('{"type":"presence","lat":1e400,"lng":0}');
      await _settle();

      expect(a.rejected('presence')?['reason'], 'invalidCoordinates');
      expect(a.closedByServer, isFalse);

      world.hub.broadcastNearbyUpdates();
      await _settle();
      expect(b.nearby(), hasLength(1));
    });

    test('a teleport is refused', () async {
      final (a, _) = await twoNeighbours();

      a.presence(lat: 10);
      await _settle();

      expect(a.rejected('presence')?['reason'], 'implausibleMovement');
    });

    test('a selfie that is not a JPEG is refused, a valid one is stored '
        'without its EXIF segment', () async {
      final bad = world.open()..hello(_secret('bad'));
      bad.presence(selfieBase64: base64Encode(utf8.encode('<html>')));
      await _settle();
      expect(bad.rejected('presence')?['reason'], 'invalidSelfie');

      final good = world.open()..hello(_secret('good'));
      good.presence(selfieBase64: base64Encode(_jpegWithExif()));
      await _settle();
      final stored = base64Decode(
        world.sessions.selfieBase64For(
          world.credentials.publicIdFor(_secret('good')),
        )!,
      );
      expect(stored, isNot(contains(0xE1)));
      expect(stored.length, _jpegWithExif().length - 10);
      expect(stored.sublist(0, 2), [0xFF, 0xD8]);
    });

    test('a chat text over the limit is rejected as invalidText, without '
        'closing the socket', () async {
      final (a, b) = await matched();
      final bForA = a.encounters('outgoing').single['otherPersonId'];

      for (final length in [
        RealtimeMessageHandler.maxChatTextLength + 1,
        5000,
      ]) {
        a.send({
          'type': 'chatMessage',
          'toPersonId': bForA,
          'text': 'a' * length,
          'clientMessageId': 'm$length',
        });
        await _settle();

        expect(a.rejected('chatMessage'), {
          'type': 'rejected',
          'action': 'chatMessage',
          'reason': 'invalidText',
          'clientMessageId': 'm$length',
        });
      }
      expect(a.closedByServer, isFalse);
      expect(b.last('chatMessage'), isNull);

      // Al limite esatto passa.
      a.send({
        'type': 'chatMessage',
        'toPersonId': bForA,
        'text': 'a' * RealtimeMessageHandler.maxChatTextLength,
      });
      await _settle();
      expect(b.last('chatMessage'), isNotNull);
    });

    test('only a frame over the much higher safety threshold closes the '
        'socket', () async {
      final (a, _) = await twoNeighbours();

      a.send({
        'type': 'chatMessage',
        'toPersonId': 'x',
        'text': 'a' * (RealtimeMessageHandler.maxChatMessageChars + 1),
      });
      await _settle();

      expect(a.closedByServer, isTrue);
    });

    test('a ping gets a pong, so the client can tell a dead socket', () async {
      final a = await world.join(_secret('a'));

      a.send({'type': 'ping'});
      await _settle();

      expect(a.last('pong'), {'type': 'pong'});
    });
  });

  group('per-viewer pseudonyms', () {
    test('two viewers see the same person under different ids, and one '
        "viewer's id means nothing to the other", () async {
      final a = await world.join(_secret('a'));
      final b = await world.join(_secret('b'));
      final c = await world.join(_secret('c'));
      world.clock = world.clock.add(const Duration(minutes: 5));
      world.hub.broadcastNearbyUpdates();
      await _settle();

      final aInternal = world.credentials.publicIdFor(_secret('a'));
      String idOfAFor(_Client viewer, String viewerSecret) => viewer
          .nearby()
          .map((p) => p['personId'] as String)
          .firstWhere(
            (id) =>
                world.pseudonyms.resolve(
                  viewerId: world.credentials.publicIdFor(viewerSecret),
                  pseudonym: id,
                ) ==
                aInternal,
          );

      final aForB = idOfAFor(b, _secret('b'));
      final aForC = idOfAFor(c, _secret('c'));
      expect(aForB, isNot(aForC));
      expect(aForB, isNot(aInternal));

      // B tries to use the id C received: it resolves to nobody for B.
      b.send({'type': 'sendEncounterRequest', 'toPersonId': aForC});
      await _settle();
      expect(b.rejected('sendEncounterRequest')?['reason'], 'notNearby');
      expect(a.encounters('incoming'), isEmpty);
    });
  });

  group('sendEncounterRequest is refused', () {
    test('for someone no longer in the list', () async {
      final (a, b) = await twoNeighbours();
      final bId = a.nearbyIdAt(0);

      // B walks ~550m away (plausible after 5 minutes).
      b.presence(lat: 0.005);
      b.presence(lat: 0.005);
      await _settle();
      a.send({'type': 'sendEncounterRequest', 'toPersonId': bId});
      await _settle();

      expect(a.rejected('sendEncounterRequest')?['reason'], 'notNearby');
      expect(b.encounters('incoming'), isEmpty);
    });

    test('for someone who is offline (in the grace period)', () async {
      final (a, b) = await twoNeighbours();
      final bId = a.nearbyIdAt(0);

      await b.dropConnection();
      await _settle();
      a.send({'type': 'sendEncounterRequest', 'toPersonId': bId});
      await _settle();

      expect(a.rejected('sendEncounterRequest')?['reason'], 'notOnline');
    });

    test('for someone behind the paywall', () async {
      final viewer = await world.join(_secret('viewer'));
      await world.join(_secret('near'), lat: 0.0001);
      await world.join(_secret('mid'), lat: 0.0002);
      await world.join(_secret('far'), lat: 0.0003);
      world.clock = world.clock.add(const Duration(minutes: 5));
      world.hub.broadcastNearbyUpdates();
      await _settle();

      // 3 people: the 2 farthest are free, the closest is locked.
      final closest = viewer.nearby().first;
      expect(closest['locked'], isTrue);
      viewer.send({
        'type': 'sendEncounterRequest',
        'toPersonId': closest['personId'],
      });
      await _settle();

      expect(viewer.rejected('sendEncounterRequest')?['reason'], 'locked');
    });

    test('a second time for the same pair, even after a decline', () async {
      final (a, b) = await twoNeighbours();
      final bId = a.nearbyIdAt(0);
      a.send({'type': 'sendEncounterRequest', 'toPersonId': bId});
      await _settle();
      b.send({
        'type': 'respondToEncounterRequest',
        'requestId': b.encounters('incoming').single['id'],
        'accepted': false,
      });
      await _settle();

      a.send({'type': 'sendEncounterRequest', 'toPersonId': bId});
      await _settle();

      expect(a.rejected('sendEncounterRequest')?['reason'], 'alreadyRequested');
      expect(b.encounters('incoming'), hasLength(1));
      // A finished request travels without selfie nor profile.
      expect(
        b.encounters('incoming').single.keys,
        isNot(contains('otherSelfieBase64')),
      );
    });

    test('when either side is already in a match', () async {
      final (a, _) = await matched();
      final c = await world.join(_secret('c'));
      world.clock = world.clock.add(const Duration(minutes: 5));
      world.hub.broadcastNearbyUpdates();
      await _settle();

      // C (not in a match) asks A (in a match with B).
      final aInternal = world.credentials.publicIdFor(_secret('a'));
      final cInternal = world.credentials.publicIdFor(_secret('c'));
      final aForC = c
          .nearby()
          .map((p) => p['personId'] as String)
          .firstWhere(
            (id) =>
                world.pseudonyms.resolve(viewerId: cInternal, pseudonym: id) ==
                aInternal,
            orElse: () => '',
          );
      expect(aForC, isNotEmpty);
      c.send({'type': 'sendEncounterRequest', 'toPersonId': aForC});
      await _settle();

      expect(c.rejected('sendEncounterRequest')?['reason'], 'inMatch');
      expect(a.encounters('incoming'), isEmpty);
    });
  });

  group('chat', () {
    test('is relayed only within a match, with per-viewer ids', () async {
      final (a, b) = await matched();
      final bForA = a.encounters('outgoing').single['otherPersonId'];
      final aForB = b.encounters('incoming').single['otherPersonId'];

      a.send({'type': 'chatMessage', 'toPersonId': bForA, 'text': 'ciao'});
      await _settle();

      final received = b.last('chatMessage')!;
      expect(received['fromPersonId'], aForB);
      expect(received['text'], 'ciao');
    });

    test('an undeliverable message is reported to the sender', () async {
      final (a, b) = await twoNeighbours();

      a.send({
        'type': 'chatMessage',
        'toPersonId': a.nearbyIdAt(0),
        'text': 'ciao',
        'clientMessageId': 'm1',
      });
      await _settle();

      expect(a.rejected('chatMessage'), {
        'type': 'rejected',
        'action': 'chatMessage',
        'reason': 'notDelivered',
        'clientMessageId': 'm1',
      });
      expect(b.last('chatMessage'), isNull);
    });
  });

  group('proposal', () {
    test('travels with the request and shows up in both sides\' '
        'snapshots, even once the request is finished', () async {
      final (a, b) = await twoNeighbours();
      a.send({
        'type': 'sendEncounterRequest',
        'toPersonId': a.nearbyIdAt(0),
        'proposal': 'drink',
      });
      await _settle();

      expect(a.encounters('outgoing').single['proposal'], 'drink');
      final incoming = b.encounters('incoming').single;
      expect(incoming['proposal'], 'drink');

      b.send({
        'type': 'respondToEncounterRequest',
        'requestId': incoming['id'],
        'accepted': false,
      });
      await _settle();

      final declined = a.encounters('outgoing').single;
      expect(declined['status'], 'declined');
      expect(declined['proposal'], 'drink');
      expect(b.encounters('incoming').single['proposal'], 'drink');
    });

    test('a missing proposal (older clients) is getToKnow', () async {
      final (a, b) = await twoNeighbours();
      a.send({'type': 'sendEncounterRequest', 'toPersonId': a.nearbyIdAt(0)});
      await _settle();

      expect(a.encounters('outgoing').single['proposal'], 'getToKnow');
      expect(b.encounters('incoming').single['proposal'], 'getToKnow');
    });

    test('an unknown proposal or free text never reaches the other person: '
        'it becomes getToKnow', () async {
      final (a, b) = await twoNeighbours();
      a.send({
        'type': 'sendEncounterRequest',
        'toPersonId': a.nearbyIdAt(0),
        'proposal': 'Wants to dance <3',
      });
      await _settle();

      expect(b.encounters('incoming').single['proposal'], 'getToKnow');
      expect(jsonEncode(b.messages), isNot(contains('dance')));
    });
  });
}
