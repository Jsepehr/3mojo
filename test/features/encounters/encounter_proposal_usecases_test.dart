import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/encounters/domain/entities/encounter_proposal.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/preselect_encounter_proposal_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/proposals_for_place_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/send_encounter_request_usecase.dart';
import 'package:threemojo_app/features/session/domain/entities/meet_place.dart';

import '../../support/fake_repositories.dart';

void main() {
  group('ProposalsForPlaceUseCase', () {
    const useCase = ProposalsForPlaceUseCase();

    test('every place offers the proposals of the agreed map, in order', () {
      expect(useCase(MeetPlace.bar), [
        EncounterProposal.drink,
        EncounterProposal.chat,
      ]);
      expect(useCase(MeetPlace.cafe), [
        EncounterProposal.chat,
        EncounterProposal.getToKnow,
      ]);
      expect(useCase(MeetPlace.club), [
        EncounterProposal.dance,
        EncounterProposal.drink,
      ]);
      expect(useCase(MeetPlace.discoPub), useCase(MeetPlace.club));
      expect(useCase(MeetPlace.event), [
        EncounterProposal.dance,
        EncounterProposal.friendship,
      ]);
      expect(useCase(MeetPlace.outdoors), [
        EncounterProposal.chat,
        EncounterProposal.friendship,
      ]);
      expect(useCase(MeetPlace.other), [
        EncounterProposal.chat,
        EncounterProposal.friendship,
        EncounterProposal.getToKnow,
        EncounterProposal.drink,
      ]);
    });

    test('every place offers something, and nothing outside the closed '
        'list', () {
      for (final place in MeetPlace.values) {
        expect(useCase(place), isNotEmpty);
        expect(useCase(place).toSet(), hasLength(useCase(place).length));
      }
    });
  });

  group('PreselectEncounterProposalUseCase', () {
    const useCase = PreselectEncounterProposalUseCase();

    test('the last proposal chosen wins while the own place still offers '
        'it', () {
      expect(
        useCase(lastChosen: EncounterProposal.chat, ownPlace: MeetPlace.bar),
        EncounterProposal.chat,
      );
    });

    test('a last choice the place does not offer is ignored: the first of '
        'the place', () {
      expect(
        useCase(lastChosen: EncounterProposal.dance, ownPlace: MeetPlace.cafe),
        EncounterProposal.chat,
      );
      expect(
        useCase(lastChosen: EncounterProposal.chat, ownPlace: MeetPlace.club),
        EncounterProposal.dance,
      );
    });

    test('without a last choice, the first of the own place', () {
      expect(useCase(ownPlace: MeetPlace.bar), EncounterProposal.drink);
      expect(useCase(ownPlace: MeetPlace.event), EncounterProposal.dance);
    });

    test('with neither, the first of "other": chat', () {
      expect(useCase(), EncounterProposal.chat);
    });
  });

  group('SendEncounterRequestUseCase', () {
    test('sends the chosen proposal along with the request', () {
      final repository = FakeEncounterRepository();

      final result = SendEncounterRequestUseCase(repository)(
        const SendEncounterRequestParams(
          otherPersonId: 'p1',
          knownRequests: [],
          proposal: EncounterProposal.chat,
        ),
      );

      expect(result.isRight(), isTrue);
      expect(repository.sentTo, ['p1']);
      expect(repository.sentProposals, [EncounterProposal.chat]);
    });

    test('an already requested person is refused before any proposal '
        'leaves', () {
      final repository = FakeEncounterRepository();

      final result = SendEncounterRequestUseCase(repository)(
        SendEncounterRequestParams(
          otherPersonId: 'p1',
          knownRequests: [
            testRequest(
              'r1',
              EncounterRequestStatus.declined,
              otherPersonId: 'p1',
            ),
          ],
          proposal: EncounterProposal.drink,
        ),
      );

      expect(result.isLeft(), isTrue);
      expect(repository.sentProposals, isEmpty);
    });
  });
}
