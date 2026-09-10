import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/chat/domain/entities/chat_message.dart';
import 'package:threemojo_app/features/chat/domain/entities/conversation.dart';
import 'package:threemojo_app/features/chat/domain/repositories/chat_repository.dart';
import 'package:threemojo_app/features/chat/domain/usecases/delete_conversation_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/encounters/domain/repositories/encounter_repository.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/end_match_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/respond_to_encounter_request_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/send_encounter_request_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/watch_encounter_requests_usecase.dart';
import 'package:threemojo_app/features/encounters/presentation/providers/pro_encounters.dart';
import 'package:threemojo_app/features/session/domain/entities/online_session.dart';
import 'package:threemojo_app/features/session/domain/repositories/session_repository.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';

typedef _Snapshot =
    ({List<EncounterRequest> incoming, List<EncounterRequest> outgoing});

EncounterRequest _request(String id, EncounterRequestStatus status) =>
    EncounterRequest(
      id: id,
      otherPersonId: 'other-$id',
      otherSelfiePath: '',
      status: status,
    );

class _FakeSessionRepository implements SessionRepository {
  @override
  Future<Either<Failure, OnlineSession?>> getCurrentSession() async => Right(
    OnlineSession(
      sessionId: 's1',
      selfiePath: '',
      selfieBytes: Uint8List(0),
      gender: Gender.male,
      genderPreference: GenderPreference.everyone,
    ),
  );

  @override
  Future<Either<Failure, OnlineSession>> startSession({
    required String sessionId,
    required String selfiePath,
    required Uint8List selfieBytes,
    required Gender gender,
    required GenderPreference genderPreference,
  }) => throw UnimplementedError('not needed for this test');

  @override
  Future<Either<Failure, Unit>> endSession() =>
      throw UnimplementedError('not needed for this test');
}

class _FakeEncounterRepository implements EncounterRepository {
  final _controller = StreamController<Either<Failure, _Snapshot>>();

  void push(_Snapshot snapshot) => _controller.add(Right(snapshot));

  void pushFailure(Failure failure) => _controller.add(Left(failure));

  @override
  Stream<Either<Failure, _Snapshot>> watchRequests(String sessionId) =>
      _controller.stream;

  @override
  void sendRequest({required String otherPersonId}) {}

  @override
  void respondToRequest({required String requestId, required bool accepted}) {}

  @override
  void endMatch(String requestId) {}
}

class _NoopChatRepository implements ChatRepository {
  @override
  Future<Either<Failure, Conversation>> getOrCreateConversation({
    required String otherPersonId,
    required String otherSelfiePath,
  }) => throw UnimplementedError('not needed for this test');

  @override
  Future<Either<Failure, List<ChatMessage>>> getMessages(
    String conversationId,
  ) => throw UnimplementedError('not needed for this test');

  @override
  Future<Either<Failure, ChatMessage>> appendMessage({
    required String conversationId,
    required String otherPersonId,
    required String text,
  }) => throw UnimplementedError('not needed for this test');

  @override
  Stream<Either<Failure, ChatMessage>> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  }) => throw UnimplementedError('not needed for this test');

  @override
  Future<Either<Failure, void>> deleteConversation(String otherPersonId) async =>
      const Right(null);
}

void main() {
  late _FakeEncounterRepository encounterRepository;
  late ProEncounters proEncounters;

  setUp(() {
    encounterRepository = _FakeEncounterRepository();
    final sessionRepository = _FakeSessionRepository();

    proEncounters = ProEncounters(
      watchEncounterRequestsUseCase: WatchEncounterRequestsUseCase(
        getCurrentSessionUseCase: GetCurrentSessionUseCase(sessionRepository),
        repository: encounterRepository,
      ),
      sendEncounterRequestUseCase: SendEncounterRequestUseCase(
        encounterRepository,
      ),
      respondToEncounterRequestUseCase: RespondToEncounterRequestUseCase(
        encounterRepository,
      ),
      endMatchUseCase: EndMatchUseCase(
        encounterRepository,
        DeleteConversationUseCase(_NoopChatRepository()),
      ),
    );
  });

  tearDown(() {
    proEncounters.dispose();
  });

  group('ProEncounters.activeMatch', () {
    test('is null when nothing is accepted yet', () async {
      encounterRepository.push((
        incoming: [_request('in1', EncounterRequestStatus.pending)],
        outgoing: [_request('out1', EncounterRequestStatus.pending)],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(proEncounters.activeMatch, isNull);
    });

    test('surfaces an accepted incoming request as the active match', () async {
      final accepted = _request('in1', EncounterRequestStatus.accepted);
      encounterRepository.push((
        incoming: [accepted],
        outgoing: [_request('out1', EncounterRequestStatus.pending)],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(proEncounters.activeMatch, accepted);
    });

    test('surfaces an accepted outgoing request when incoming has none', () async {
      final accepted = _request('out1', EncounterRequestStatus.accepted);
      encounterRepository.push((
        incoming: [_request('in1', EncounterRequestStatus.declined)],
        outgoing: [accepted],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(proEncounters.activeMatch, accepted);
    });
  });

  test('pendingIncomingCount only counts pending incoming requests', () async {
    encounterRepository.push((
      incoming: [
        _request('in1', EncounterRequestStatus.pending),
        _request('in2', EncounterRequestStatus.pending),
        _request('in3', EncounterRequestStatus.declined),
      ],
      outgoing: [],
    ));
    await Future<void>.delayed(Duration.zero);

    expect(proEncounters.pendingIncomingCount, 2);
  });

  test('a failed snapshot surfaces its message without clearing the lists', () async {
    encounterRepository.push((
      incoming: [_request('in1', EncounterRequestStatus.pending)],
      outgoing: [],
    ));
    await Future<void>.delayed(Duration.zero);

    encounterRepository.pushFailure(const ValidationFailure('boom'));
    await Future<void>.delayed(Duration.zero);

    expect(proEncounters.errorMessage, 'boom');
    expect(proEncounters.incomingRequests, hasLength(1));
  });
}
