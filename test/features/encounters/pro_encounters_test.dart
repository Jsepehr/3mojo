import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_proposal.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_rejection.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/find_lost_encounter_requests_usecase.dart';
import 'package:threemojo_app/features/encounters/presentation/encounter_notice.dart';
import 'package:threemojo_app/features/encounters/presentation/providers/pro_encounters.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/session/domain/entities/online_session.dart';
import 'package:threemojo_app/features/session/domain/entities/server_handshake.dart';

import '../../support/build_providers.dart';
import '../../support/fake_repositories.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

OnlineSession _sessionWithIntent(String id, MeetIntent? intent) =>
    OnlineSession(
      sessionId: id,
      selfieBytes: testSession(id).selfieBytes,
      profile: testProfile,
      intent: intent,
    );

void main() {
  late FakeSessionRepository sessions;
  late FakeEncounterRepository encounters;
  late FakeChatRepository chat;
  late FakeConnectionRepository connection;
  late ProEncounters proEncounters;
  late List<EncounterNotice> notices;

  setUp(() async {
    sessions = FakeSessionRepository(current: testSession('s1'));
    encounters = FakeEncounterRepository();
    chat = FakeChatRepository();
    connection = FakeConnectionRepository();
    proEncounters = buildProEncounters(
      sessions: sessions,
      encounters: encounters,
      chat: chat,
      connection: connection,
    );
    notices = [];
    proEncounters.notices.listen(notices.add);
    await _settle();
  });

  tearDown(() => proEncounters.dispose());

  group('activeMatch', () {
    test('is null when nothing is accepted yet', () async {
      encounters.push((
        incoming: [testRequest('in1', EncounterRequestStatus.pending)],
        outgoing: [testRequest('out1', EncounterRequestStatus.pending)],
      ));
      await _settle();

      expect(proEncounters.activeMatch, isNull);
    });

    test('surfaces an accepted incoming request', () async {
      final accepted = testRequest('in1', EncounterRequestStatus.accepted);
      encounters.push((incoming: [accepted], outgoing: []));
      await _settle();

      expect(proEncounters.activeMatch, accepted);
    });

    test('surfaces an accepted outgoing request', () async {
      final accepted = testRequest('out1', EncounterRequestStatus.accepted);
      encounters.push((
        incoming: [testRequest('in1', EncounterRequestStatus.declined)],
        outgoing: [accepted],
      ));
      await _settle();

      expect(proEncounters.activeMatch, accepted);
    });
  });

  test('pendingIncomingCount only counts pending incoming requests', () async {
    encounters.push((
      incoming: [
        testRequest('in1', EncounterRequestStatus.pending),
        testRequest('in2', EncounterRequestStatus.pending),
        testRequest('in3', EncounterRequestStatus.declined),
      ],
      outgoing: [],
    ));
    await _settle();

    expect(proEncounters.pendingIncomingCount, 2);
  });

  group('session lifecycle', () {
    test('a connection drop keeps what is already shown', () async {
      encounters.push((
        incoming: [testRequest('in1', EncounterRequestStatus.pending)],
        outgoing: [],
      ));
      await _settle();

      encounters.pushFailure(const ConnectionFailure('socket closed'));
      await _settle();

      expect(proEncounters.incomingRequests, hasLength(1));
    });

    test('NotOnlineFailure empties the lists (no stale badge)', () async {
      encounters.push((
        incoming: [testRequest('in1', EncounterRequestStatus.pending)],
        outgoing: [testRequest('out1', EncounterRequestStatus.pending)],
      ));
      await _settle();

      encounters.pushFailure(const NotOnlineFailure('No active session'));
      await _settle();

      expect(proEncounters.incomingRequests, isEmpty);
      expect(proEncounters.outgoingRequests, isEmpty);
      expect(proEncounters.pendingIncomingCount, 0);
    });

    test('End empties the lists and stops listening', () async {
      encounters.push((
        incoming: [testRequest('in1', EncounterRequestStatus.pending)],
        outgoing: [],
      ));
      await _settle();

      sessions.end();
      await _settle();

      expect(proEncounters.pendingIncomingCount, 0);
      expect(encounters.hasListeners, isFalse);
    });

    test('does not listen to the server while offline', () async {
      sessions.end();
      await _settle();
      final callsBefore = encounters.watchCalls;

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(encounters.watchCalls, callsBefore);
    });

    test(
      'a server-side restart resets requests and forgets the match chat',
      () async {
        encounters.push((
          incoming: [
            testRequest(
              'in1',
              EncounterRequestStatus.accepted,
              otherPersonId: 'p1',
            ),
          ],
          outgoing: [],
        ));
        await _settle();

        connection.handshakes.add(
          const ServerHandshake(resumed: false, isFirstOfSession: false),
        );
        await _settle();

        expect(proEncounters.activeMatch, isNull);
        expect(proEncounters.incomingRequests, isEmpty);
        expect(chat.deleted, ['p1']);
        expect(notices.whereType<MatchEndedByPartnerNotice>(), isEmpty);
      },
    );
  });

  group('ending a match', () {
    test('ending it locally ignores a snapshot still in flight', () async {
      final match = testRequest(
        'm1',
        EncounterRequestStatus.accepted,
        otherPersonId: 'p1',
      );
      encounters.push((incoming: [match], outgoing: []));
      await _settle();

      final result = await proEncounters.endMatch(
        requestId: 'm1',
        otherPersonId: 'p1',
      );
      // Uno snapshot partito prima della fine, che lo mostra ancora accettato.
      encounters.push((incoming: [match], outgoing: []));
      await _settle();

      expect(result.isRight(), isTrue);
      expect(proEncounters.activeMatch, isNull);
      expect(notices.whereType<MatchEndedByPartnerNotice>(), isEmpty);
    });

    test('if the end cannot leave, the match stays and the failure is '
        'returned', () async {
      encounters.endMatchResult = const Left(ConnectionFailure('offline'));
      final match = testRequest('m1', EncounterRequestStatus.accepted);
      encounters.push((incoming: [match], outgoing: []));
      await _settle();

      final result = await proEncounters.endMatch(
        requestId: 'm1',
        otherPersonId: match.otherPersonId,
      );

      expect(result.getLeft().toNullable(), isA<ConnectionFailure>());
      expect(proEncounters.activeMatch, match);
      expect(chat.deleted, isEmpty);
    });

    test('ended by the other person: notice and chat forgotten', () async {
      encounters.push((
        incoming: [
          testRequest(
            'm1',
            EncounterRequestStatus.accepted,
            otherPersonId: 'p1',
          ),
        ],
        outgoing: [],
      ));
      await _settle();

      encounters.push((
        incoming: [
          testRequest('m1', EncounterRequestStatus.ended, otherPersonId: 'p1'),
        ],
        outgoing: [],
      ));
      await _settle();

      expect(proEncounters.activeMatch, isNull);
      expect(notices.whereType<MatchEndedByPartnerNotice>(), hasLength(1));
      expect(chat.deleted, ['p1']);
    });
  });

  group('sending a request', () {
    test('is "requested" right after it leaves, and confirmed by the '
        'snapshot', () async {
      proEncounters.sendRequest('p1');

      expect(proEncounters.hasRequested('p1'), isTrue);
      expect(notices, isEmpty);

      encounters.push((
        incoming: [],
        outgoing: [
          testRequest(
            'o1',
            EncounterRequestStatus.pending,
            otherPersonId: 'p1',
          ),
        ],
      ));
      await _settle();

      expect(notices.single, isA<RequestSentNotice>());
      expect(proEncounters.hasRequested('p1'), isTrue);
    });

    test('offline: not marked as requested, says why', () async {
      encounters.sendResult = const Left(ConnectionFailure('offline'));

      proEncounters.sendRequest('p1');
      await _settle();

      expect(proEncounters.hasRequested('p1'), isFalse);
      final notice = notices.single as ActionNotSentNotice;
      expect(notice.failure, isA<ConnectionFailure>());
    });

    test('rejected by the server: no longer "requested", says why', () async {
      proEncounters.sendRequest('p1');
      encounters.reject(
        const EncounterRejection(
          action: EncounterAction.sendRequest,
          reason: EncounterRejectionReason.notNearby,
          otherPersonId: 'p1',
        ),
      );
      await _settle();

      expect(proEncounters.hasRequested('p1'), isFalse);
      final notice = notices.single as ActionRejectedNotice;
      expect(notice.rejection.reason, EncounterRejectionReason.notNearby);
    });

    test('a second tap on the same person does not send twice', () async {
      proEncounters.sendRequest('p1');
      proEncounters.sendRequest('p1');
      await _settle();

      expect(encounters.sentTo, ['p1']);
      final notice = notices.single as ActionNotSentNotice;
      expect(notice.failure, isA<AlreadyRequestedFailure>());
    });
  });

  test('a response that cannot leave is reported', () async {
    encounters.respondResult = const Left(ConnectionFailure('offline'));

    proEncounters.respondToRequest('in1', true);
    await _settle();

    final notice = notices.single as ActionNotSentNotice;
    expect(notice.action, EncounterAction.respondToRequest);
  });

  group('a request that is never confirmed', () {
    const timeout = FindLostEncounterRequestsUseCase.confirmationTimeout;

    test('is considered lost after the confirmation time: the person can be '
        'requested again and the user is told', () {
      fakeAsync((async) {
        final start = DateTime(2026, 1, 1, 12);
        final provider = buildProEncounters(
          sessions: FakeSessionRepository(current: testSession('s1')),
          encounters: FakeEncounterRepository(),
          chat: FakeChatRepository(),
          now: () => start.add(async.elapsed),
        );
        final seen = <EncounterNotice>[];
        provider.notices.listen(seen.add);
        async.flushMicrotasks();

        provider.sendRequest('p1');
        async.elapse(timeout - const Duration(seconds: 1));
        expect(provider.hasRequested('p1'), isTrue);
        expect(seen, isEmpty);

        async.elapse(const Duration(seconds: 1));
        expect(provider.hasRequested('p1'), isFalse);
        expect(seen.single, isA<ActionNotSentNotice>());
        final notice = seen.single as ActionNotSentNotice;
        expect(notice.action, EncounterAction.sendRequest);
        expect(notice.failure, isA<RequestNotConfirmedFailure>());

        provider.dispose();
      });
    });

    test('each request has its own deadline; a confirmed one is never '
        'expired', () {
      fakeAsync((async) {
        final start = DateTime(2026, 1, 1, 12);
        final repository = FakeEncounterRepository();
        final provider = buildProEncounters(
          sessions: FakeSessionRepository(current: testSession('s1')),
          encounters: repository,
          chat: FakeChatRepository(),
          now: () => start.add(async.elapsed),
        );
        final seen = <EncounterNotice>[];
        provider.notices.listen(seen.add);
        async.flushMicrotasks();

        provider.sendRequest('p1');
        async.elapse(const Duration(seconds: 4));
        provider.sendRequest('p2');
        repository.push((
          incoming: [],
          outgoing: [
            testRequest(
              'r1',
              EncounterRequestStatus.pending,
              otherPersonId: 'p1',
            ),
          ],
        ));
        async.flushMicrotasks();
        expect(seen.single, isA<RequestSentNotice>());

        async.elapse(timeout - const Duration(seconds: 4));
        expect(provider.hasRequested('p1'), isTrue); // confermata
        expect(provider.hasRequested('p2'), isTrue); // non ancora scaduta

        async.elapse(const Duration(seconds: 4));
        expect(provider.hasRequested('p2'), isFalse);
        expect(seen.last, isA<ActionNotSentNotice>());
        expect(seen, hasLength(2));

        provider.dispose();
      });
    });
  });

  group('proposal', () {
    test('without a choice yet, the preselection follows the own session '
        'intent', () async {
      sessions.start(_sessionWithIntent('s2', MeetIntent.friendship));
      await _settle();

      expect(proEncounters.preselectedProposal, EncounterProposal.friendship);
    });

    test('with no intent at all, getToKnow', () async {
      expect(proEncounters.preselectedProposal, EncounterProposal.getToKnow);
    });

    test('a request carries its proposal, which becomes the next '
        'preselection', () async {
      sessions.start(_sessionWithIntent('s2', MeetIntent.chat));
      await _settle();

      proEncounters.sendRequest('p1', proposal: EncounterProposal.drink);

      expect(encounters.sentProposals, [EncounterProposal.drink]);
      expect(proEncounters.preselectedProposal, EncounterProposal.drink);
    });

    test('a request that did not leave does not change the preselection', () {
      encounters.sendResult = const Left(ConnectionFailure('offline'));

      proEncounters.sendRequest('p1', proposal: EncounterProposal.drink);

      expect(proEncounters.preselectedProposal, EncounterProposal.getToKnow);
    });

    test('End forgets the last choice: the next session starts again from '
        'its own intent', () async {
      proEncounters.sendRequest('p1', proposal: EncounterProposal.drink);
      sessions.end();
      await _settle();
      sessions.start(_sessionWithIntent('s3', MeetIntent.chat));
      await _settle();

      expect(proEncounters.preselectedProposal, EncounterProposal.chat);
    });

    test('the proposal matching the other person\'s public intent', () {
      expect(
        proEncounters.proposalMatchingIntent(MeetIntent.chat),
        EncounterProposal.chat,
      );
      expect(
        proEncounters.proposalMatchingIntent(MeetIntent.meetPeople),
        EncounterProposal.getToKnow,
      );
      expect(proEncounters.proposalMatchingIntent(null), isNull);
    });
  });
}
