import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/encounters/domain/entities/encounter_proposal.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/preselect_encounter_proposal_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/proposal_for_intent_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/send_encounter_request_usecase.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';

import '../../support/fake_repositories.dart';

void main() {
  group('ProposalForIntentUseCase', () {
    const useCase = ProposalForIntentUseCase();

    test('☕ and 🤝 have their own proposal', () {
      expect(useCase(MeetIntent.chat), EncounterProposal.chat);
      expect(useCase(MeetIntent.friendship), EncounterProposal.friendship);
    });

    test('🙂, ✨ and no intent fall back to getToKnow', () {
      expect(useCase(MeetIntent.meetPeople), EncounterProposal.getToKnow);
      expect(useCase(MeetIntent.openToAnything), EncounterProposal.getToKnow);
      expect(useCase(null), EncounterProposal.getToKnow);
    });
  });

  group('PreselectEncounterProposalUseCase', () {
    const useCase = PreselectEncounterProposalUseCase();

    test('the last proposal chosen in this session wins over the intent', () {
      expect(
        useCase(
          lastChosen: EncounterProposal.drink,
          ownIntent: MeetIntent.chat,
        ),
        EncounterProposal.drink,
      );
    });

    test('without a last choice, the one paired with the own intent', () {
      expect(useCase(ownIntent: MeetIntent.chat), EncounterProposal.chat);
      expect(
        useCase(ownIntent: MeetIntent.friendship),
        EncounterProposal.friendship,
      );
      expect(
        useCase(ownIntent: MeetIntent.openToAnything),
        EncounterProposal.getToKnow,
      );
    });

    test('with neither, getToKnow', () {
      expect(useCase(), EncounterProposal.getToKnow);
    });
  });

  group('SendEncounterRequestUseCase', () {
    test('sends the chosen proposal along with the request', () {
      final repository = FakeEncounterRepository();

      final result = SendEncounterRequestUseCase(repository)(
        const SendEncounterRequestParams(
          otherPersonId: 'p1',
          knownRequests: [],
          proposal: EncounterProposal.sayHi,
        ),
      );

      expect(result.isRight(), isTrue);
      expect(repository.sentTo, ['p1']);
      expect(repository.sentProposals, [EncounterProposal.sayHi]);
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
