import 'package:test/test.dart';
import 'package:threemojo_server/src/encounter_store.dart';

void main() {
  group('EncounterStore', () {
    late EncounterStore store;

    setUp(() {
      store = EncounterStore.empty();
    });

    test('sendRequest creates a pending request visible to both sides', () {
      final request = store.sendRequest(fromSessionId: 'a', toSessionId: 'b');

      expect(request.status, EncounterRequestStatus.pending);
      expect(store.outgoingFor('a').map((r) => r.id), contains(request.id));
      expect(store.incomingFor('b').map((r) => r.id), contains(request.id));
    });

    test('declining sets the status without touching other requests', () {
      final declined = store.sendRequest(fromSessionId: 'a', toSessionId: 'b');
      final untouched = store.sendRequest(fromSessionId: 'a', toSessionId: 'c');

      final result = store.respondToRequest(
        requestId: declined.id,
        accepted: false,
        bySessionId: 'b',
      );

      expect(result.request.status, EncounterRequestStatus.declined);
      expect(result.alsoCancelled, isEmpty);
      expect(
        store.outgoingFor('a').firstWhere((r) => r.id == untouched.id).status,
        EncounterRequestStatus.pending,
      );
    });

    test(
      'accepting cancels every other pending request for both participants',
      () {
        final accepted = store.sendRequest(fromSessionId: 'a', toSessionId: 'b');
        // 'a' has another outgoing request to 'c'.
        final aToC = store.sendRequest(fromSessionId: 'a', toSessionId: 'c');
        // 'b' has another incoming request from 'd'.
        final dToB = store.sendRequest(fromSessionId: 'd', toSessionId: 'b');
        // Unrelated to either 'a' or 'b': must survive untouched.
        final unrelated = store.sendRequest(fromSessionId: 'e', toSessionId: 'f');

        final result = store.respondToRequest(
          requestId: accepted.id,
          accepted: true,
          bySessionId: 'b',
        );

        expect(result.request.status, EncounterRequestStatus.accepted);
        expect(
          result.alsoCancelled.map((r) => r.id),
          containsAll([aToC.id, dToB.id]),
        );
        expect(
          store.outgoingFor('a').firstWhere((r) => r.id == aToC.id).status,
          EncounterRequestStatus.cancelled,
        );
        expect(
          store.incomingFor('b').firstWhere((r) => r.id == dToB.id).status,
          EncounterRequestStatus.cancelled,
        );
        expect(
          store
              .outgoingFor('e')
              .firstWhere((r) => r.id == unrelated.id)
              .status,
          EncounterRequestStatus.pending,
        );
      },
    );

    test('endMatch marks a request as ended', () {
      final request = store.sendRequest(fromSessionId: 'a', toSessionId: 'b');
      store.respondToRequest(
        requestId: request.id,
        accepted: true,
        bySessionId: 'b',
      );

      final ended = store.endMatch(request.id, bySessionId: 'a');

      expect(ended.status, EncounterRequestStatus.ended);
      expect(store.hasActiveMatch('a', 'b'), isFalse);
    });

    test('only the recipient can respond, and only while pending', () {
      final request = store.sendRequest(fromSessionId: 'a', toSessionId: 'b');

      // Né il mittente né un estraneo possono rispondere al posto di 'b'.
      expect(
        () => store.respondToRequest(
          requestId: request.id,
          accepted: true,
          bySessionId: 'a',
        ),
        throwsArgumentError,
      );
      expect(
        () => store.respondToRequest(
          requestId: request.id,
          accepted: true,
          bySessionId: 'intruder',
        ),
        throwsArgumentError,
      );
      expect(request.status, EncounterRequestStatus.pending);

      store.respondToRequest(
        requestId: request.id,
        accepted: false,
        bySessionId: 'b',
      );
      // Una volta rifiutata non si può più ribaltare la risposta.
      expect(
        () => store.respondToRequest(
          requestId: request.id,
          accepted: true,
          bySessionId: 'b',
        ),
        throwsArgumentError,
      );
      expect(request.status, EncounterRequestStatus.declined);
    });

    test('only a participant can end an active match', () {
      final request = store.sendRequest(fromSessionId: 'a', toSessionId: 'b');

      // Non ancora accettata: niente match da chiudere.
      expect(
        () => store.endMatch(request.id, bySessionId: 'a'),
        throwsArgumentError,
      );

      store.respondToRequest(
        requestId: request.id,
        accepted: true,
        bySessionId: 'b',
      );
      expect(store.hasActiveMatch('a', 'b'), isTrue);
      expect(
        () => store.endMatch(request.id, bySessionId: 'intruder'),
        throwsArgumentError,
      );
      expect(request.status, EncounterRequestStatus.accepted);
    });

    test('hasActiveMatch is false for pending, declined and unrelated pairs', () {
      final pending = store.sendRequest(fromSessionId: 'a', toSessionId: 'b');
      final declined = store.sendRequest(fromSessionId: 'c', toSessionId: 'd');
      store.respondToRequest(
        requestId: declined.id,
        accepted: false,
        bySessionId: 'd',
      );

      expect(store.hasActiveMatch(pending.fromSessionId, 'b'), isFalse);
      expect(store.hasActiveMatch('c', 'd'), isFalse);
      expect(store.hasActiveMatch('a', 'd'), isFalse);
    });

    test('cancelAllPendingFor cancels only pending requests for a session', () {
      final asSender = store.sendRequest(fromSessionId: 'a', toSessionId: 'b');
      final asReceiver = store.sendRequest(fromSessionId: 'c', toSessionId: 'a');
      final alreadyDeclined = store.sendRequest(
        fromSessionId: 'a',
        toSessionId: 'd',
      );
      store.respondToRequest(
        requestId: alreadyDeclined.id,
        accepted: false,
        bySessionId: 'd',
      );

      final affected = store.cancelAllPendingFor('a');

      expect(affected.map((r) => r.id), containsAll([asSender.id, asReceiver.id]));
      expect(affected.map((r) => r.id), isNot(contains(alreadyDeclined.id)));
    });
  });
}
