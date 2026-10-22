import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:threemojo_server/src/block_store.dart';
import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/encounter_store.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/moderation_records.dart';
import 'package:threemojo_server/src/moderation_store.dart';
import 'package:threemojo_server/src/new_session_rate_limiter.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/pseudonyms.dart';
import 'package:threemojo_server/src/realtime_message_handler.dart';
import 'package:threemojo_server/src/report_reason.dart';
import 'package:threemojo_server/src/session_credentials.dart';
import 'package:threemojo_server/src/session_lifecycle.dart';
import 'package:threemojo_server/src/session_store.dart';
import 'package:threemojo_server/src/socket_session.dart';

final _key = List<int>.generate(32, (i) => i);
final _otherKey = List<int>.generate(32, (i) => 255 - i);

/// Come `_World` di socket_session_test.dart, più blocchi, segnalazioni e
/// record di moderazione su una cartella temporanea.
class _World {
  _World(Directory recordsDir) {
    sessions = SessionStore.withClock(() => clock);
    paywall = PaywallStore.withClock(() => clock);
    hotspots = HotspotStore.withClock(() => clock);
    moderation = ModerationStore.withClock(() => clock);
    records = ModerationRecordStore(
      directory: recordsDir,
      key: _key,
      now: () => clock,
    );
    hub = ConnectionHub.withStore(
      sessions,
      encounterStore: encounters,
      paywallStore: paywall,
      hotspotStore: hotspots,
      pseudonyms: pseudonyms,
      blockStore: blocks,
      broadcastThrottleInterval: Duration.zero,
      nearbyPushMinInterval: Duration.zero,
    );
    rateLimiter = NewSessionRateLimiter.withClock(() => clock, limit: 100);
    lifecycle = SessionLifecycle(
      sessions: sessions,
      encounters: encounters,
      hub: hub,
      credentials: credentials,
      rateLimiter: rateLimiter,
      blocks: blocks,
      moderation: moderation,
      gracePeriod: const Duration(milliseconds: 150),
      now: () => clock,
    );
    handler = RealtimeMessageHandler(
      sessions: sessions,
      encounters: encounters,
      hub: hub,
      paywall: paywall,
      hotspots: hotspots,
      blocks: blocks,
      moderation: moderation,
      records: records,
      lifecycle: lifecycle,
      now: () => clock,
    );
  }

  DateTime clock = DateTime.utc(2026, 1, 1, 10, 0, 37);
  late final SessionStore sessions;
  final encounters = EncounterStore.empty();
  late final PaywallStore paywall;
  late final HotspotStore hotspots;
  final pseudonyms = Pseudonyms();
  final blocks = BlockStore.empty();
  late final ModerationStore moderation;
  late final ModerationRecordStore records;
  late final ConnectionHub hub;
  final credentials = SessionCredentials.empty();
  late final NewSessionRateLimiter rateLimiter;
  late final SessionLifecycle lifecycle;
  late final RealtimeMessageHandler handler;

  _Client open({String ip = '10.0.0.1'}) {
    final client = _Client();
    SocketSession(
      incoming: client.toServer.stream,
      outgoing: client.fromServer,
      clientIp: ip,
      lifecycle: lifecycle,
      handler: handler,
    ).start();
    return client;
  }

  Future<_Client> join(
    String name, {
    bool presence = true,
    String ip = '10.0.0.1',
  }) async {
    final client = open(ip: ip)..hello(_secret(name));
    if (presence) {
      client.send({
        'type': 'presence',
        'lat': 0,
        'lng': 0,
        'selfieBase64': base64Encode(_jpeg(name)),
      });
    }
    await _settle();
    return client;
  }

  String internal(String name) => credentials.publicIdFor(_secret(name));

  /// Lo pseudonimo con cui [viewer] vede [target] (lo stesso che riceve
  /// nelle liste).
  String idFor(String viewer, String target) =>
      pseudonyms.idFor(viewerId: internal(viewer), targetId: internal(target));

  /// Tutti fermi da 5 minuti: ognuno vede gli altri.
  Future<void> settleDwell() async {
    clock = clock.add(const Duration(minutes: 5));
    hub.broadcastNearbyUpdates();
    await _settle();
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
  Future<void> dropConnection() => toServer.close();

  Map<String, dynamic>? last(String type) {
    for (final m in messages.reversed) {
      if (m['type'] == type) return m;
    }
    return null;
  }

  List<Map<String, dynamic>> nearby() =>
      ((last('nearby')?['people'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  List<String> nearbyIds() => [
    for (final p in nearby()) p['personId'] as String,
  ];

  List<Map<String, dynamic>> encounters(String direction) =>
      ((last('encounters')?[direction] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  Map<String, dynamic>? rejected(String action) {
    for (final m in messages.reversed) {
      if (m['type'] == 'rejected' && m['action'] == action) return m;
    }
    return null;
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

String _secret(String name) => '$name-secret'.padRight(36, 'x');

/// Un JPEG minimo strutturalmente valido, diverso per ogni nome.
Uint8List _jpeg(String name) => Uint8List.fromList([
  0xFF, 0xD8, // SOI
  0xFF, 0xDA, 0x00, 0x04, 0x01, 0x02, // SOS
  ...utf8.encode(name), // dati "compressi"
  0xFF, 0xD9, // EOI
]);

void main() {
  late Directory tempDir;
  late _World world;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moderation_test');
    world = _World(Directory('${tempDir.path}/records'));
  });
  tearDown(() async {
    world.dispose();
    await world.records.flush();
    await tempDir.delete(recursive: true);
  });

  Future<(_Client, _Client)> neighbours() async {
    final a = await world.join('a');
    final b = await world.join('b');
    await world.settleDwell();
    return (a, b);
  }

  Future<(_Client, _Client)> matchedIn(_World w) async {
    final a = await w.join('a');
    final b = await w.join('b');
    await w.settleDwell();
    a.send({'type': 'sendEncounterRequest', 'toPersonId': w.idFor('a', 'b')});
    await _settle();
    b.send({
      'type': 'respondToEncounterRequest',
      'requestId': b.encounters('incoming').single['id'],
      'accepted': true,
    });
    await _settle();
    expect(b.encounters('incoming').single['status'], 'accepted');
    return (a, b);
  }

  group('block', () {
    test('works both ways in "nearby"', () async {
      final (a, b) = await neighbours();
      expect(a.nearby(), hasLength(1));
      expect(b.nearby(), hasLength(1));

      a.send({'type': 'block', 'personId': world.idFor('a', 'b')});
      await _settle();

      expect(a.nearby(), isEmpty);
      expect(b.nearby(), isEmpty);
      expect(a.rejected('block'), isNull);
    });

    test('nearbyPeople leaves out blocked people in both directions', () {
      var now = DateTime(2026);
      final store = SessionStore.withClock(() => now)
        ..upsertPosition(sessionId: 'x', lat: 0, lng: 0)
        ..upsertPosition(sessionId: 'y', lat: 0, lng: 0.0001);
      now = now.add(const Duration(minutes: 5));
      final blocks = BlockStore.empty()..block('y', 'x');

      List<NearbyPersonResult>? seenBy(String id, BlockStore blockStore) =>
          store.nearbyPeople(
            sessionId: id,
            radiusMeters: 100,
            hotspotStore: HotspotStore.withClock(() => now),
            paywallStore: PaywallStore.withClock(() => now),
            blockStore: blockStore,
          );
      expect(seenBy('x', BlockStore.empty()), hasLength(1));
      expect(seenBy('x', blocks), isEmpty);
      expect(seenBy('y', blocks), isEmpty);
    });

    test('survives a reconnection within the grace of either side', () async {
      final (a, b) = await neighbours();
      a.send({'type': 'block', 'personId': world.idFor('a', 'b')});
      await _settle();

      await a.dropConnection();
      await _settle();
      final a2 = await world.join('a', presence: false);
      expect(a2.last('welcome')?['resumed'], isTrue);

      await b.dropConnection();
      await _settle();
      final b2 = await world.join('b', presence: false);
      expect(b2.last('welcome')?['resumed'], isTrue);

      world.hub.broadcastNearbyUpdates();
      await _settle();
      expect(a2.nearby(), isEmpty);
      expect(b2.nearby(), isEmpty);
      expect(
        world.blocks.isBlockedEitherWay(
          world.internal('a'),
          world.internal('b'),
        ),
        isTrue,
      );
    });

    test('is forgotten when the session of the blocker ends', () async {
      final (a, _) = await neighbours();
      a.send({'type': 'block', 'personId': world.idFor('a', 'b')});
      await _settle();

      a.send({'type': 'end'});
      await _settle();

      expect(world.blocks.blockerCount, 0);
    });

    test('cancels pending requests in both directions, then they are '
        'gone', () async {
      final a = await world.join('a');
      final b = await world.join('b');
      final c = await world.join('c');
      await world.settleDwell();
      a.send({
        'type': 'sendEncounterRequest',
        'toPersonId': world.idFor('a', 'b'),
      });
      c.send({
        'type': 'sendEncounterRequest',
        'toPersonId': world.idFor('c', 'b'),
      });
      await _settle();
      expect(b.encounters('incoming'), hasLength(2));

      b.send({'type': 'block', 'personId': world.idFor('b', 'a')});
      await _settle();

      // A (blocked) sees its request cancelled, exactly as if B had left.
      expect(a.encounters('outgoing').single['status'], 'cancelled');
      // B (blocker) no longer has it; C's request is untouched.
      expect(
        b.encounters('incoming').single['otherPersonId'],
        world.idFor('b', 'c'),
      );
      expect(world.encounters.length, 1);
    });

    test('a new request with the old pseudonym is notNearby, chat is '
        'notDelivered, block/report are unknownPerson', () async {
      final (a, b) = await neighbours();
      final bForA = world.idFor('a', 'b');
      final aForB = world.idFor('b', 'a');

      a.send({'type': 'block', 'personId': bForA});
      await _settle();

      b.send({'type': 'sendEncounterRequest', 'toPersonId': aForB});
      b.send({
        'type': 'chatMessage',
        'toPersonId': aForB,
        'text': 'ciao',
        'clientMessageId': 'm1',
      });
      b.send({'type': 'block', 'personId': aForB});
      b.send({'type': 'report', 'personId': aForB, 'reason': 'spam'});
      a.send({'type': 'sendEncounterRequest', 'toPersonId': bForA});
      await _settle();

      expect(b.rejected('sendEncounterRequest')?['reason'], 'notNearby');
      expect(b.rejected('chatMessage')?['reason'], 'notDelivered');
      expect(b.rejected('block')?['reason'], 'unknownPerson');
      expect(b.rejected('report')?['reason'], 'unknownPerson');
      expect(a.rejected('sendEncounterRequest')?['reason'], 'notNearby');
      // Chi ha bloccato può ancora segnalare.
      a.send({'type': 'report', 'personId': bForA, 'reason': 'spam'});
      await _settle();
      expect(a.rejected('report'), isNull);
    });

    test('an unknown pseudonym or oneself is unknownPerson', () async {
      final (a, _) = await neighbours();
      a.send({'type': 'block', 'personId': 'nope'});
      a.send({'type': 'block'});
      await _settle();

      expect(a.rejected('block'), {
        'type': 'rejected',
        'action': 'block',
        'reason': 'unknownPerson',
      });
      expect(a.messages.where((m) => m['type'] == 'rejected'), hasLength(2));
      expect(world.blocks.blockerCount, 0);
    });

    test('closes the match: the blocked person sees exactly what they would '
        'see if the other person pressed End', () async {
      List<Object?> normalized(List<Map<String, dynamic>> messages) => [
        for (final m in messages)
          if (m['type'] == 'encounters')
            {
              for (final direction in ['incoming', 'outgoing'])
                direction: [
                  for (final r
                      in (m[direction] as List).cast<Map<String, dynamic>>())
                    {
                      for (final e in r.entries)
                        e.key: e.key == 'id' || e.key == 'otherPersonId'
                            ? '<id>'
                            : e.value,
                    },
                ],
            }
          else if (m['type'] == 'nearby')
            {'nearby': (m['people'] as List).length}
          else
            m,
      ];

      // Scenario 1: A blocks B.
      final (a1, b1) = await matchedIn(world);
      final before1 = b1.messages.length;
      a1.send({'type': 'block', 'personId': world.idFor('a', 'b')});
      await _settle();
      final afterBlock = normalized(b1.messages.sublist(before1));

      // Scenario 2: A presses End.
      final otherDir = await Directory.systemTemp.createTemp('moderation_2');
      final world2 = _World(Directory('${otherDir.path}/r'));
      final (a2, b2) = await matchedIn(world2);
      final before2 = b2.messages.length;
      a2.send({'type': 'end'});
      await _settle();
      final afterEnd = normalized(b2.messages.sublist(before2));
      world2.dispose();
      await otherDir.delete(recursive: true);

      expect(afterBlock, isNotEmpty);
      expect(afterBlock, afterEnd);
      expect(b1.encounters('incoming').single['status'], 'ended');
      expect(b1.nearby(), isEmpty);
      expect(world.encounters.length, 0);
    });
  });

  group('report', () {
    Future<List<_Client>> crowd(Map<String, String> ipByName) async {
      final clients = <_Client>[];
      for (final entry in ipByName.entries) {
        clients.add(await world.join(entry.key, ip: entry.value));
      }
      await world.settleDwell();
      return clients;
    }

    void report(
      _Client client,
      String from,
      String to, [
      String reason = 'spam',
    ]) => client.send({
      'type': 'report',
      'personId': world.idFor(from, to),
      'reason': reason,
    });

    test('3 reports from different sessions on 2 IPs close the session and '
        'start a cooldown on its IP', () async {
      final clients = await crowd({
        't': '10.0.0.9',
        'r1': '10.0.0.1',
        'r2': '10.0.0.2',
        'r3': '10.0.0.1',
      });
      final t = clients[0];
      final tInternal = world.internal('t');

      report(clients[1], 'r1', 't', 'fakePhoto');
      report(clients[2], 'r2', 't', 'fakePhoto');
      await _settle();
      expect(t.closedByServer, isFalse);
      expect(t.last('sessionClosed'), isNull);

      report(clients[3], 'r3', 't', 'harassment');
      await _settle();

      expect(t.last('sessionClosed'), {
        'type': 'sessionClosed',
        'reason': 'reports',
      });
      expect(t.closedByServer, isTrue);
      expect(world.sessions.contains(tInternal), isFalse);
      expect(clients[1].nearbyIds(), hasLength(2)); // r2, r3: t is gone

      // New Starts from that IP are refused during the cooldown, the old
      // secret included (its session is over).
      final again = world.open(ip: '10.0.0.9')..hello(_secret('t'));
      final other = world.open(ip: '10.0.0.9')..hello(_secret('someone'));
      final elsewhere = world.open(ip: '10.0.0.7')..hello(_secret('x'));
      await _settle();
      expect(again.last('error')?['code'], 'rateLimited');
      expect(other.last('error')?['code'], 'rateLimited');
      expect(elsewhere.last('welcome'), isNotNull);

      world.clock = world.clock.add(ModerationConfig.defaultCooldown);
      final later = world.open(ip: '10.0.0.9')..hello(_secret('t'));
      await _settle();
      expect(later.last('welcome')?['resumed'], isFalse);

      await world.records.flush();
      final records = await world.records.list();
      expect(records, hasLength(1));
      expect(records.single.reportCount, 3);
      expect(records.single.autoClosed, isTrue);
      expect(records.single.reasons, {'fakePhoto': 2, 'harassment': 1});
    });

    test('3 reports all from the same IP do not close the session', () async {
      final clients = await crowd({
        't': '10.0.0.9',
        'r1': '10.0.0.1',
        'r2': '10.0.0.1',
        'r3': '10.0.0.1',
      });
      report(clients[1], 'r1', 't');
      report(clients[2], 'r2', 't');
      report(clients[3], 'r3', 't');
      await _settle();

      expect(clients[0].closedByServer, isFalse);
      expect(
        world.moderation.tallyFor(world.internal('t'))?.reporters,
        hasLength(3),
      );
    });

    test('a duplicate report from the same session does not count', () async {
      final clients = await crowd({
        't': '10.0.0.9',
        'r1': '10.0.0.1',
        'r2': '10.0.0.2',
      });
      report(clients[1], 'r1', 't');
      report(clients[1], 'r1', 't', 'other');
      report(clients[1], 'r1', 't');
      report(clients[2], 'r2', 't');
      await _settle();

      final tally = world.moderation.tallyFor(world.internal('t'))!;
      expect(tally.reporters, hasLength(2));
      expect(tally.reasons, {ReportReason.spam: 2});
      expect(clients[1].rejected('report'), isNull);
      expect(clients[0].closedByServer, isFalse);
    });

    test(
      'the 6th report is tooManyReports, but the block still applies',
      () async {
        final names = {
          'r': '10.0.0.1',
          for (var i = 0; i < 6; i++) 't$i': '10.0.0.${i + 2}',
        };
        final clients = await crowd(names);
        final r = clients.first;
        for (var i = 0; i < ModerationStore.maxReportsPerSession; i++) {
          report(r, 'r', 't$i');
        }
        await _settle();
        expect(r.rejected('report'), isNull);

        report(r, 'r', 't5');
        await _settle();

        expect(r.rejected('report'), {
          'type': 'rejected',
          'action': 'report',
          'reason': 'tooManyReports',
          'personId': world.idFor('r', 't5'),
        });
        expect(
          world.blocks.isBlockedEitherWay(
            world.internal('r'),
            world.internal('t5'),
          ),
          isTrue,
        );
        expect(world.moderation.tallyFor(world.internal('t5')), isNull);
        expect(r.nearby(), isEmpty);
      },
    );

    test('an invalid reason does nothing at all', () async {
      final (a, _) = await neighbours();
      for (final reason in ['lol', null, 42]) {
        a.send({
          'type': 'report',
          'personId': world.idFor('a', 'b'),
          'reason': ?reason,
        });
      }
      await _settle();

      expect(a.rejected('report')?['reason'], 'invalidReason');
      expect(world.blocks.blockerCount, 0);
      expect(world.moderation.tallyFor(world.internal('b')), isNull);
      expect(a.nearby(), hasLength(1));
      await world.records.flush();
      expect(await world.records.list(), isEmpty);
    });

    test(
      'the record holds only the allowed fields, encrypted on disk',
      () async {
        final (a, _) = await neighbours();
        a.send({
          'type': 'chatMessage',
          'toPersonId': world.idFor('a', 'b'),
          'text': 'segreto',
        });
        report(a, 'a', 'b', 'inappropriatePhoto');
        await _settle();
        await world.records.flush();

        final files = world.records.directory
            .listSync()
            .whereType<File>()
            .toList();
        expect(files, hasLength(1));
        final bytes = files.single.readAsBytesSync();
        final raw = latin1.decode(bytes);
        final selfie = base64Encode(_jpeg('b'));
        expect(raw, isNot(contains(selfie)));
        expect(raw, isNot(contains('inappropriatePhoto')));
        expect(raw, isNot(contains('reportCount')));

        final record = (await world.records.list()).single;
        final json = record.toJson();
        expect(json.keys.toSet(), {
          'id',
          'createdAt',
          'updatedAt',
          'reasons',
          'reportCount',
          'autoClosed',
          'selfieBase64',
        });
        expect(json['selfieBase64'], selfie);
        expect(jsonEncode(json), isNot(contains('segreto')));
        expect(jsonEncode(json), isNot(contains('10.0.0.1')));
        expect(jsonEncode(json), isNot(contains(world.internal('b'))));
        expect(jsonEncode(json), isNot(contains(world.idFor('a', 'b'))));
        expect(record.createdAt, DateTime.utc(2026, 1, 1, 10, 5));
        expect(record.createdAt.second, 0);
        expect(record.reportCount, 1);
        expect(record.autoClosed, isFalse);
      },
    );

    test('one record per reported session, updated by later reports', () async {
      final clients = await crowd({
        't': '10.0.0.9',
        'r1': '10.0.0.1',
        'r2': '10.0.0.2',
      });
      report(clients[1], 'r1', 't', 'spam');
      await _settle();
      world.clock = world.clock.add(const Duration(minutes: 3));
      report(clients[2], 'r2', 't', 'underage');
      await _settle();
      await world.records.flush();

      expect(
        world.records.directory.listSync().whereType<File>(),
        hasLength(1),
      );
      final record = (await world.records.list()).single;
      expect(record.reportCount, 2);
      expect(record.reasons, {'spam': 1, 'underage': 1});
      expect(record.updatedAt.difference(record.createdAt).inMinutes, 3);
    });
  });

  group('ModerationRecordStore', () {
    ModerationRecord sample(String id, DateTime at) => ModerationRecord(
      id: id,
      createdAt: at,
      updatedAt: at,
      reasons: const {'spam': 1},
      reportCount: 1,
      autoClosed: false,
      selfieBase64: base64Encode(_jpeg('z')),
    );
    const id = '0123456789abcdef0123456789abcdef';

    test('only the right key decrypts a record', () async {
      final dir = Directory('${tempDir.path}/keys');
      final store = ModerationRecordStore(directory: dir, key: _key);
      await store.save(sample(id, DateTime.utc(2026)));

      expect((await store.read(id))?.reportCount, 1);
      final wrong = ModerationRecordStore(directory: dir, key: _otherKey);
      expect(await wrong.read(id), isNull);
      expect(await wrong.list(), isEmpty);
    });

    test('a renamed file does not decrypt (the id is authenticated)', () async {
      final dir = Directory('${tempDir.path}/rename');
      final store = ModerationRecordStore(directory: dir, key: _key);
      await store.save(sample(id, DateTime.utc(2026)));
      const otherId = 'ffffffffffffffffffffffffffffffff';
      File('${dir.path}/$id.rec').renameSync('${dir.path}/$otherId.rec');

      expect(await store.read(otherId), isNull);
    });

    test('without a key nothing is written', () async {
      final dir = Directory('${tempDir.path}/nokey');
      final store = ModerationRecordStore.fromEnvironment({
        'MODERATION_DIR': dir.path,
      });
      expect(store.isEnabled, isFalse);
      expect(store.configurationProblem, contains('MODERATION_KEY'));
      await store.save(sample(id, DateTime.utc(2026)));
      expect(dir.existsSync(), isFalse);

      final short = ModerationRecordStore.fromEnvironment({
        'MODERATION_KEY': base64Encode([1, 2, 3]),
      });
      expect(short.isEnabled, isFalse);
      final good = ModerationRecordStore.fromEnvironment({
        'MODERATION_KEY': base64Encode(_key),
        'MODERATION_DIR': dir.path,
      });
      expect(good.isEnabled, isTrue);
      expect(good.directory.path, dir.path);
    });

    test('records are purged 30 days after createdAt', () async {
      var now = DateTime.utc(2026, 3, 5);
      final dir = Directory('${tempDir.path}/purge');
      final store = ModerationRecordStore(
        directory: dir,
        key: _key,
        now: () => now,
      );
      const oldId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await store.save(sample(oldId, DateTime.utc(2026, 2, 1)));
      await store.save(sample(id, DateTime.utc(2026, 2, 20)));

      expect(await store.purgeExpired(), 1);
      expect(await store.read(oldId), isNull);
      expect(await store.read(id), isNotNull);

      now = DateTime.utc(2026, 3, 22);
      expect(await store.purgeExpired(), 1);
      expect(await store.list(), isEmpty);
    });

    test('an undecryptable file is purged by its modification date', () async {
      final dir = Directory('${tempDir.path}/stale');
      await ModerationRecordStore(
        directory: dir,
        key: _otherKey,
      ).save(sample(id, DateTime.utc(2026)));

      final soon = ModerationRecordStore(
        directory: dir,
        key: _key,
        now: () => DateTime.now().add(const Duration(days: 29)),
      );
      expect(await soon.purgeExpired(), 0);
      final late = ModerationRecordStore(
        directory: dir,
        key: _key,
        now: () => DateTime.now().add(const Duration(days: 31)),
      );
      expect(await late.purgeExpired(), 1);
    });

    test('ids that are not 32 lowercase hex digits never touch the disk', () {
      expect(ModerationRecordStore.isValidId(id), isTrue);
      for (final bad in ['../etc/passwd', 'ABCDEF', '', '$id/..', '${id}0']) {
        expect(ModerationRecordStore.isValidId(bad), isFalse, reason: bad);
      }
    });
  });

  group('ModerationConfig', () {
    test('reads the environment, ignoring invalid values', () {
      final config = ModerationConfig.fromEnvironment({
        'MODERATION_AUTO_CLOSE_REPORTS': '5',
        'MODERATION_AUTO_CLOSE_MIN_IPS': 'x',
        'MODERATION_COOLDOWN_MINUTES': '0',
      });
      expect(config.autoCloseReports, 5);
      expect(config.autoCloseMinIps, ModerationConfig.defaultAutoCloseMinIps);
      expect(config.cooldown, Duration.zero);
      expect(
        ModerationConfig.fromEnvironment(const {}).cooldown,
        ModerationConfig.defaultCooldown,
      );
    });

    test('with no known IP the IP condition is ignored, and a zero '
        'cooldown does nothing', () {
      final store = ModerationStore.withClock(
        () => DateTime(2026),
        config: const ModerationConfig(cooldown: Duration.zero),
      );
      ReportOutcome reportFrom(String reporter) => store.report(
        reporterId: reporter,
        reporterIp: '',
        reportedId: 't',
        reason: ReportReason.other,
      );
      reportFrom('r1');
      reportFrom('r2');
      expect(reportFrom('r3').shouldAutoClose, isTrue);
      expect(reportFrom('r4').shouldAutoClose, isFalse);

      store.startCooldown('10.0.0.1');
      expect(store.isInCooldown('10.0.0.1'), isFalse);
    });
  });
}
