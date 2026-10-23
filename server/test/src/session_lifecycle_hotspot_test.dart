import 'package:test/test.dart';
import 'package:threemojo_server/src/block_store.dart';
import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/encounter_store.dart';
import 'package:threemojo_server/src/hotspot_store.dart';
import 'package:threemojo_server/src/moderation_store.dart';
import 'package:threemojo_server/src/new_session_rate_limiter.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/pseudonyms.dart';
import 'package:threemojo_server/src/session_credentials.dart';
import 'package:threemojo_server/src/session_lifecycle.dart';
import 'package:threemojo_server/src/session_store.dart';

/// La fine di una sessione (`SessionLifecycle.endNow`) toglie il suo id
/// interno anche dai membri degli hotspot, non solo da `SessionStore`.
void main() {
  late DateTime clock;
  late SessionStore sessions;
  late HotspotStore hotspots;
  late ConnectionHub hub;
  late SessionLifecycle lifecycle;

  setUp(() {
    clock = DateTime.utc(2026, 1, 1, 10);
    sessions = SessionStore.withClock(() => clock);
    hotspots = HotspotStore.withClock(() => clock);
    final encounters = EncounterStore.empty();
    final blocks = BlockStore.empty();
    hub = ConnectionHub.withStore(
      sessions,
      encounterStore: encounters,
      paywallStore: PaywallStore.withClock(() => clock),
      hotspotStore: hotspots,
      pseudonyms: Pseudonyms(),
      blockStore: blocks,
      broadcastThrottleInterval: Duration.zero,
      nearbyPushMinInterval: Duration.zero,
    );
    lifecycle = SessionLifecycle(
      sessions: sessions,
      encounters: encounters,
      hub: hub,
      credentials: SessionCredentials.empty(),
      rateLimiter: NewSessionRateLimiter.withClock(() => clock),
      blocks: blocks,
      moderation: ModerationStore.withClock(() => clock),
      now: () => clock,
    );
  });

  tearDown(() {
    lifecycle.dispose();
    hub.stopHotspotDetection();
  });

  test('endNow removes the internal id from the hotspot members', () {
    sessions.upsertPosition(sessionId: 'a', lat: 0.0000, lng: 0.0000);
    sessions.upsertPosition(sessionId: 'b', lat: 0.0001, lng: 0.0000);
    sessions.upsertPosition(sessionId: 'c', lat: 0.0000, lng: 0.0001);
    clock = clock.add(const Duration(minutes: 16));
    hotspots.detectAndRefresh(sessions.allSessions);
    // Come fa `SessionStore.nearbyPeople` per chi è oltre il raggio
    // diretto: registra l'appartenenza (con isteresi) di entrambi.
    expect(hotspots.sharesAnyActiveHotspot('a', 0, 0, 'b', 0.0001, 0), isTrue);
    expect(
      hotspots.sharesAnyActiveHotspot('c', 0, 0.0001, 'b', 0.0001, 0),
      isTrue,
    );
    final hotspot = hotspots.active.single;
    expect(hotspot.memberSessionIds, {'a', 'b', 'c'});

    lifecycle.endNow('a');

    expect(hotspot.memberSessionIds, {'b', 'c'});
    expect(hotspots.active.single, same(hotspot));
  });
}
