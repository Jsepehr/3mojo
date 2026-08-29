import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/session_store.dart';

void main() {
  group('ConnectionHub', () {
    late DateTime clock;
    late SessionStore store;
    late ConnectionHub hub;

    setUp(() {
      clock = DateTime(2026, 1, 1);
      store = SessionStore.withClock(() => clock);
      hub = ConnectionHub.withStore(store);
    });

    test('broadcasts each registered session its own nearby list', () async {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final aMessages = <dynamic>[];
      final bMessages = <dynamic>[];
      hub.register('a', StreamController<dynamic>()..stream.listen(aMessages.add));
      hub.register('b', StreamController<dynamic>()..stream.listen(bMessages.add));

      hub.broadcastNearbyUpdates();
      await Future<void>.delayed(Duration.zero);

      final aPayload = jsonDecode(aMessages.single as String) as Map<String, dynamic>;
      expect(aPayload['type'], 'nearby');
      expect((aPayload['people'] as List).single['sessionId'], 'b');

      final bPayload = jsonDecode(bMessages.single as String) as Map<String, dynamic>;
      expect((bPayload['people'] as List).single['sessionId'], 'a');
    });

    test('unregister stops further pushes to that session', () async {
      store.upsertPosition(sessionId: 'a', lat: 0, lng: 0);
      store.upsertPosition(sessionId: 'b', lat: 0, lng: 0);
      clock = clock.add(const Duration(minutes: 5));

      final aMessages = <dynamic>[];
      hub.register('a', StreamController<dynamic>()..stream.listen(aMessages.add));
      hub.unregister('a');

      hub.broadcastNearbyUpdates();
      await Future<void>.delayed(Duration.zero);

      expect(aMessages, isEmpty);
    });
  });
}
