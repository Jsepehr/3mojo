import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/chat/domain/usecases/delete_conversation_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/encounters/domain/entities/match_end.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/detect_ended_match_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/end_match_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/find_lost_encounter_requests_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/forget_ended_match_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/has_requested_person_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/respond_to_encounter_request_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/send_encounter_request_usecase.dart';

import '../../support/fake_repositories.dart';

void main() {
  late FakeEncounterRepository repository;

  setUp(() => repository = FakeEncounterRepository());

  group('HasRequestedPersonUseCase (one request per person)', () {
    const useCase = HasRequestedPersonUseCase();

    test('any request with that person counts, sent or received, in any '
        'state', () {
      for (final status in EncounterRequestStatus.values) {
        expect(
          useCase(
            'p1',
            requests: [testRequest('r', status, otherPersonId: 'p1')],
          ),
          isTrue,
          reason: status.name,
        );
      }
    });

    test('a request that just left counts too', () {
      expect(
        useCase('p1', requests: const [], awaitingPersonIds: {'p1'}),
        isTrue,
      );
    });

    test('someone else does not count', () {
      expect(
        useCase(
          'p1',
          requests: [
            testRequest(
              'r',
              EncounterRequestStatus.pending,
              otherPersonId: 'p2',
            ),
          ],
        ),
        isFalse,
      );
    });
  });

  group('SendEncounterRequestUseCase', () {
    test('sends to a person never asked', () {
      final result = SendEncounterRequestUseCase(repository)(
        const SendEncounterRequestParams(
          otherPersonId: 'p1',
          knownRequests: [],
        ),
      );

      expect(result.isRight(), isTrue);
      expect(repository.sentTo, ['p1']);
    });

    test('refuses a second request to the same person, without sending', () {
      final result = SendEncounterRequestUseCase(repository)(
        SendEncounterRequestParams(
          otherPersonId: 'p1',
          knownRequests: [
            testRequest(
              'r',
              EncounterRequestStatus.declined,
              otherPersonId: 'p1',
            ),
          ],
        ),
      );

      expect(result.getLeft().toNullable(), isA<AlreadyRequestedFailure>());
      expect(repository.sentTo, isEmpty);
    });

    test('propagates "not sent" from the repository', () {
      repository.sendResult = const Left(ConnectionFailure('offline'));

      final result = SendEncounterRequestUseCase(repository)(
        const SendEncounterRequestParams(
          otherPersonId: 'p1',
          knownRequests: [],
        ),
      );

      expect(result.getLeft().toNullable(), isA<ConnectionFailure>());
    });
  });

  group('RespondToEncounterRequestUseCase', () {
    test('forwards the answer and returns Right when it left', () {
      final result = RespondToEncounterRequestUseCase(repository)(
        const RespondToEncounterRequestParams(requestId: 'r1', accepted: true),
      );

      expect(result.isRight(), isTrue);
      expect(repository.responses, [('r1', true)]);
    });

    test('returns the failure when it could not leave', () {
      repository.respondResult = const Left(ConnectionFailure('offline'));

      final result = RespondToEncounterRequestUseCase(repository)(
        const RespondToEncounterRequestParams(requestId: 'r1', accepted: false),
      );

      expect(result.getLeft().toNullable(), isA<ConnectionFailure>());
    });
  });

  group('EndMatchUseCase', () {
    test('ends the match and then forgets the chat', () async {
      final chat = FakeChatRepository();

      final result = await EndMatchUseCase(
        repository,
        DeleteConversationUseCase(chat),
      )(requestId: 'm1', otherPersonId: 'p1');

      expect(result, const Right<Failure, Unit>(unit));
      expect(repository.endedMatches, ['m1']);
      expect(chat.deleted, ['p1']);
    });

    test('if the end cannot leave, the chat stays and the failure is '
        'returned', () async {
      repository.endMatchResult = const Left(ConnectionFailure('offline'));
      final chat = FakeChatRepository();

      final result = await EndMatchUseCase(
        repository,
        DeleteConversationUseCase(chat),
      )(requestId: 'm1', otherPersonId: 'p1');

      expect(result.getLeft().toNullable(), isA<ConnectionFailure>());
      expect(chat.deleted, isEmpty);
    });
  });

  group('DetectEndedMatchUseCase', () {
    late FakeChatRepository chat;
    late DetectEndedMatchUseCase useCase;
    final match = testRequest(
      'm1',
      EncounterRequestStatus.accepted,
      otherPersonId: 'p1',
    );
    final ended = testRequest(
      'm1',
      EncounterRequestStatus.ended,
      otherPersonId: 'p1',
    );

    setUp(() {
      chat = FakeChatRepository();
      useCase = DetectEndedMatchUseCase(
        ForgetEndedMatchUseCase(DeleteConversationUseCase(chat)),
      );
    });

    test('a match that disappears is ended by the partner, and its chat is '
        'forgotten', () async {
      final result = await useCase(previous: [match], next: [ended]);

      expect(
        result,
        MatchEnd(match: match, reason: MatchEndReason.endedByPartner),
      );
      expect(chat.deleted, ['p1']);
    });

    test('nothing happens while the match is still there, or if there was '
        'none', () async {
      expect(await useCase(previous: [match], next: [match]), isNull);
      expect(await useCase(previous: [], next: [ended]), isNull);
      expect(chat.deleted, isEmpty);
    });

    test(
      'a match you are ending yourself is not "ended by the partner"',
      () async {
        final result = await useCase(
          previous: [match],
          next: [ended],
          endingIds: {'m1'},
        );

        expect(result, isNull);
        expect(chat.deleted, isEmpty);
      },
    );

    test('a match you already closed locally does not count', () async {
      final result = await useCase(
        previous: [match],
        next: [ended],
        locallyEndedIds: {'m1'},
      );

      expect(result, isNull);
    });

    test('a server restart ends the match whatever the snapshot says, and '
        'forgets its chat', () async {
      final result = await useCase(
        previous: [match],
        next: [match],
        sessionRestarted: true,
      );

      expect(result?.reason, MatchEndReason.sessionRestarted);
      expect(chat.deleted, ['p1']);
    });
    test('a match with someone you blocked ends because of you: reason '
        '"blocked", never "ended by the partner", and the chat goes', () async {
      final result = await useCase(
        previous: [match],
        next: [match],
        blockedPersonIds: {'p1'},
      );

      expect(result?.reason, MatchEndReason.blocked);
      expect(chat.deleted, ['p1']);
    });
  });

  group('FindLostEncounterRequestsUseCase', () {
    const useCase = FindLostEncounterRequestsUseCase();
    final sentAt = DateTime(2026, 1, 1, 12);

    test('a request is lost only once the confirmation time has passed', () {
      const timeout = FindLostEncounterRequestsUseCase.confirmationTimeout;
      final awaiting = {'old': sentAt, 'new': sentAt.add(timeout ~/ 2)};

      expect(
        useCase(
          awaiting,
          now: sentAt.add(timeout - const Duration(seconds: 1)),
        ),
        isEmpty,
      );
      expect(useCase(awaiting, now: sentAt.add(timeout)), {'old'});
      expect(useCase(awaiting, now: sentAt.add(timeout * 2)), {'old', 'new'});
    });
  });
}
