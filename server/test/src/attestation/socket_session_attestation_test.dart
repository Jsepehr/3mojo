import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:threemojo_server/src/attestation/attestation_config.dart';
import 'package:threemojo_server/src/attestation/attestation_gate.dart';
import 'package:threemojo_server/src/attestation/attestation_verifier.dart';
import 'package:threemojo_server/src/attestation/fake_attestation_verifier.dart';
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

/// Un verificatore che si può far aspettare (per vedere cosa succede ai
/// messaggi che arrivano durante la verifica).
class _GatedVerifier implements AttestationVerifier {
  Completer<void> release = Completer<void>()..complete();

  @override
  AttestationPlatform get platform => AttestationPlatform.android;

  @override
  Future<void> verify(AttestationEvidence evidence, {required String nonce}) =>
      release.future;
}

class _World {
  _World(AttestationMode mode) {
    sessions = SessionStore.withClock(() => clock);
    hub = ConnectionHub.withStore(
      sessions,
      encounterStore: encounters,
      paywallStore: PaywallStore.withClock(() => clock),
      hotspotStore: HotspotStore.withClock(() => clock),
      pseudonyms: Pseudonyms(),
      broadcastThrottleInterval: Duration.zero,
      nearbyPushMinInterval: Duration.zero,
    );
    lifecycle = SessionLifecycle(
      sessions: sessions,
      encounters: encounters,
      hub: hub,
      credentials: credentials,
      rateLimiter: NewSessionRateLimiter.withClock(() => clock),
      gracePeriod: const Duration(milliseconds: 150),
      now: () => clock,
    );
    handler = RealtimeMessageHandler(
      sessions: sessions,
      encounters: encounters,
      hub: hub,
      paywall: PaywallStore.withClock(() => clock),
      hotspots: HotspotStore.withClock(() => clock),
    );
    gate = AttestationGate(
      mode: mode,
      verifiers: {
        AttestationPlatform.fake: const FakeAttestationVerifier(),
        AttestationPlatform.android: android,
      },
      log: logLines.add,
    );
  }

  DateTime clock = DateTime(2026, 1, 1);
  late final SessionStore sessions;
  final encounters = EncounterStore.empty();
  late final ConnectionHub hub;
  final credentials = SessionCredentials.empty();
  late final SessionLifecycle lifecycle;
  late final RealtimeMessageHandler handler;
  late final AttestationGate gate;
  final android = _GatedVerifier();
  final logLines = <String>[];

  _Client open({Duration attestationTimeout = const Duration(seconds: 5)}) {
    final client = _Client();
    SocketSession(
      incoming: client.toServer.stream,
      outgoing: client.fromServer,
      clientIp: '10.0.0.1',
      lifecycle: lifecycle,
      handler: handler,
      attestation: gate,
      attestationTimeout: attestationTimeout,
    ).start();
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

  List<String?> get types => [for (final m in messages) m['type'] as String?];

  String get nonce =>
      messages.firstWhere((m) => m['type'] == 'challenge')['nonce'] as String;

  void attestFake({String? nonce}) => send({
    'type': 'attestation',
    'platform': 'fake',
    'token': FakeAttestationVerifier.tokenFor(nonce ?? this.nonce),
  });
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

const _secret = 'attested-session-secret-xxxxxxxxxxxxxxx';

void main() {
  late _World world;

  tearDown(() => world.dispose());

  test('off: no challenge, hello is answered with welcome as before', () async {
    world = _World(AttestationMode.off);
    final client = world.open()..hello(_secret);
    await _settle();
    expect(client.types.first, 'welcome');
    expect(client.types, isNot(contains('challenge')));
  });

  group('enforce', () {
    setUp(() => world = _World(AttestationMode.enforce));

    test('a new session gets a challenge first, and nothing is registered '
        'before the outcome', () async {
      final client = world.open()..hello(_secret);
      await _settle();

      expect(client.types, ['challenge']);
      final challenge = client.messages.single;
      expect(challenge['nonce'], isA<String>());
      expect(challenge['expiresInSeconds'], 20);
      expect(world.credentials.knows(_secret), isFalse);
    });

    test('a valid attestation for this nonce opens the session', () async {
      final client = world.open()..hello(_secret);
      await _settle();
      client.attestFake();
      await _settle();

      expect(client.types, containsAllInOrder(['challenge', 'welcome']));
      expect(client.messages[1]['resumed'], isFalse);
      expect(world.credentials.knows(_secret), isTrue);
      expect(client.closedByServer, isFalse);
    });

    test('without a valid attestation: attestationRequired, closed, nothing '
        'registered', () async {
      for (final answer in [
        {'type': 'attestation'},
        {'type': 'attestation', 'platform': 'fake', 'token': 'forged'},
      ]) {
        final client = world.open()..hello(_secret);
        await _settle();
        client.send(answer);
        await _settle();

        expect(client.types, ['challenge', 'error']);
        expect(client.messages.last['code'], 'attestationRequired');
        expect(client.closedByServer, isTrue);
        expect(world.credentials.knows(_secret), isFalse);
      }
    });

    test("an attestation for another socket's nonce is refused", () async {
      final first = world.open()..hello(_secret);
      final second = world.open()
        ..hello('another-secret-xxxxxxxxxxxxxxxxxxxxxxx');
      await _settle();
      second.attestFake(nonce: first.nonce);
      await _settle();
      expect(second.messages.last['code'], 'attestationRequired');
    });

    test('no answer to the challenge in time closes the socket', () async {
      final client = world.open(
        attestationTimeout: const Duration(milliseconds: 20),
      )..hello(_secret);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(client.types, ['challenge', 'error']);
      expect(client.messages.last['code'], 'attestationRequired');
      expect(client.closedByServer, isTrue);
    });

    test(
      'anything else instead of the attestation closes the socket',
      () async {
        final client = world.open()..hello(_secret);
        await _settle();
        client.send({'type': 'presence', 'lat': 0, 'lng': 0});
        await _settle();
        expect(client.closedByServer, isTrue);
        expect(world.credentials.knows(_secret), isFalse);
      },
    );

    test('a reconnection of a live session is not attested again', () async {
      final first = world.open()..hello(_secret);
      await _settle();
      first.attestFake();
      await _settle();
      await first.toServer.close();
      await _settle();

      final again = world.open()..hello(_secret);
      await _settle();
      expect(again.types.first, 'welcome');
      expect(again.messages.first['resumed'], isTrue);
    });

    test('messages arriving during the verification wait for its '
        'outcome', () async {
      world.android.release = Completer<void>();
      final client = world.open()..hello(_secret);
      await _settle();
      client
        ..send({'type': 'attestation', 'platform': 'android', 'token': 't'})
        ..send({'type': 'ping'});
      await _settle();
      expect(client.types, ['challenge']);

      world.android.release.complete();
      await _settle();
      expect(client.types, ['challenge', 'welcome', 'encounters', 'pong']);
    });
  });

  test('log: an invalid attestation is written down but the session '
      'opens', () async {
    world = _World(AttestationMode.log);
    final client = world.open()..hello(_secret);
    await _settle();
    client.send({'type': 'attestation'});
    await _settle();
    expect(client.types, containsAllInOrder(['challenge', 'welcome']));
    expect(world.logLines.single, contains('missing'));
    expect(world.gate.counts[AttestationOutcome.missing], 1);
  });

  test('log: a client that never answers still gets in after the '
      'timeout', () async {
    world = _World(AttestationMode.log);
    final client = world.open(
      attestationTimeout: const Duration(milliseconds: 20),
    )..hello(_secret);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(client.types, containsAllInOrder(['challenge', 'welcome']));
    expect(world.gate.counts[AttestationOutcome.timeout], 1);
  });
}
