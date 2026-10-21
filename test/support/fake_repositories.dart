import 'dart:async';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/chat/domain/entities/chat_message.dart';
import 'package:threemojo_app/features/chat/domain/entities/conversation.dart';
import 'package:threemojo_app/features/chat/domain/repositories/chat_repository.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_proposal.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_rejection.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/encounters/domain/repositories/encounter_repository.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:threemojo_app/features/session/domain/entities/connection_status.dart';
import 'package:threemojo_app/features/session/domain/entities/online_session.dart';
import 'package:threemojo_app/features/session/domain/entities/server_handshake.dart';
import 'package:threemojo_app/features/session/domain/repositories/connection_repository.dart';
import 'package:threemojo_app/features/session/domain/repositories/face_detection_repository.dart';
import 'package:threemojo_app/features/session/domain/repositories/session_repository.dart';

const testProfile = Profile(
  gender: Gender.male,
  lookingFor: Profile.searchableGenders,
  isAdultConfirmed: true,
  sensitiveDataConsent: true,
);

OnlineSession testSession(String id) => OnlineSession(
  sessionId: id,
  selfieBytes: Uint8List(0),
  profile: testProfile,
);

/// Sessione in memoria pilotabile dal test: [start]/[end] la cambiano e
/// avvisano chi ascolta [watchSession], come il datasource vero.
class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository({OnlineSession? current}) : _current = current;

  OnlineSession? _current;
  int endSessionCalls = 0;
  final _changes = StreamController<OnlineSession?>.broadcast(sync: true);

  OnlineSession? get current => _current;

  void start(OnlineSession session) {
    _current = session;
    _changes.add(session);
  }

  void end() {
    _current = null;
    _changes.add(null);
  }

  @override
  Future<Either<Failure, OnlineSession?>> getCurrentSession() async =>
      Right(_current);

  @override
  Future<Either<Failure, OnlineSession>> startSession({
    required String sessionId,
    required Uint8List selfieBytes,
    required Profile profile,
    MeetIntent? intent,
  }) async {
    final session = OnlineSession(
      sessionId: sessionId,
      selfieBytes: selfieBytes,
      profile: profile,
      intent: intent,
    );
    start(session);
    return Right(session);
  }

  @override
  Future<Either<Failure, Unit>> endSession() async {
    endSessionCalls++;
    end();
    return const Right(unit);
  }

  @override
  Stream<OnlineSession?> watchSession() => Stream.multi((controller) {
    controller.add(_current);
    final subscription = _changes.stream.listen(controller.add);
    controller.onCancel = subscription.cancel;
  });
}

class FakeConnectionRepository implements ConnectionRepository {
  final status = StreamController<ConnectionStatus>.broadcast();
  final handshakes = StreamController<ServerHandshake>.broadcast();

  @override
  Stream<ConnectionStatus> watchStatus() => status.stream;

  @override
  Stream<ServerHandshake> watchHandshakes() => handshakes.stream;

  int checkCalls = 0;

  @override
  void checkConnection() => checkCalls++;
}

typedef Snapshot = ({
  List<EncounterRequest> incoming,
  List<EncounterRequest> outgoing,
});

EncounterRequest testRequest(
  String id,
  EncounterRequestStatus status, {
  String? otherPersonId,
}) => EncounterRequest(
  id: id,
  otherPersonId: otherPersonId ?? 'other-$id',
  status: status,
);

/// Richieste pilotabili dal test: uno stream di snapshot e uno di rifiuti
/// per ogni ascolto (come una connessione), più l'esito delle azioni.
class FakeEncounterRepository implements EncounterRepository {
  final _snapshots = StreamController<Either<Failure, Snapshot>>.broadcast();
  final _rejections = StreamController<EncounterRejection>.broadcast();

  Either<Failure, Unit> sendResult = const Right(unit);
  Either<Failure, Unit> respondResult = const Right(unit);
  Either<Failure, Unit> endMatchResult = const Right(unit);
  final sentTo = <String>[];
  final sentProposals = <EncounterProposal>[];
  final responses = <(String, bool)>[];
  final endedMatches = <String>[];
  int watchCalls = 0;
  int clearCalls = 0;

  bool get hasListeners => _snapshots.hasListener;

  void push(Snapshot snapshot) => _snapshots.add(Right(snapshot));

  void pushFailure(Failure failure) => _snapshots.add(Left(failure));

  void reject(EncounterRejection rejection) => _rejections.add(rejection);

  @override
  Stream<Either<Failure, Snapshot>> watchRequests(String sessionId) {
    watchCalls++;
    return _snapshots.stream;
  }

  @override
  Stream<EncounterRejection> watchRejections(String sessionId) =>
      _rejections.stream;

  @override
  Either<Failure, Unit> sendRequest({
    required String otherPersonId,
    required EncounterProposal proposal,
  }) {
    sentTo.add(otherPersonId);
    sentProposals.add(proposal);
    return sendResult;
  }

  @override
  Either<Failure, Unit> respondToRequest({
    required String requestId,
    required bool accepted,
  }) {
    responses.add((requestId, accepted));
    return respondResult;
  }

  @override
  Either<Failure, Unit> endMatch(String requestId) {
    endedMatches.add(requestId);
    return endMatchResult;
  }

  @override
  Future<Either<Failure, Unit>> clearSessionState() async {
    clearCalls++;
    return const Right(unit);
  }
}

/// Chat in memoria pilotabile dal test.
class FakeChatRepository implements ChatRepository {
  final incoming = StreamController<Either<Failure, ChatMessage>>.broadcast();
  final undelivered = StreamController<String>.broadcast();
  final deleted = <String>[];
  final opened = <String>[];
  Either<Failure, ChatMessage>? appendResult;
  int clearCalls = 0;
  int _counter = 0;

  @override
  Future<Either<Failure, Conversation>> getOrCreateConversation({
    required String otherPersonId,
    Uint8List? otherSelfieBytes,
  }) async {
    opened.add(otherPersonId);
    return Right(
      Conversation(id: 'conv-$otherPersonId', otherPersonId: otherPersonId),
    );
  }

  @override
  Future<Either<Failure, List<ChatMessage>>> getMessages(
    String conversationId,
  ) async => const Right([]);

  @override
  Future<Either<Failure, ChatMessage>> appendMessage({
    required String conversationId,
    required String otherPersonId,
    required String text,
  }) async =>
      appendResult ??
      Right(
        ChatMessage(
          id: 'msg-${_counter++}',
          isMine: true,
          text: text,
          sentAt: DateTime(2026),
        ),
      );

  final startedReceiving = <String>[];

  @override
  Either<Failure, Unit> startReceivingMessages({required String sessionId}) {
    startedReceiving.add(sessionId);
    return const Right(unit);
  }

  @override
  Stream<Either<Failure, ChatMessage>> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  }) => incoming.stream;

  @override
  Stream<String> watchUndeliveredMessageIds({required String sessionId}) =>
      undelivered.stream;

  @override
  Future<Either<Failure, void>> deleteConversation(String otherPersonId) async {
    deleted.add(otherPersonId);
    return const Right(null);
  }

  @override
  Future<Either<Failure, Unit>> clearSessionState() async {
    clearCalls++;
    return const Right(unit);
  }
}

/// Profilo in memoria pilotabile dal test, con il segno di installazione.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.saved, this.hasInstallMarker = true});

  Profile? saved;
  bool hasInstallMarker;
  Either<Failure, Profile?>? getResult;
  Either<Failure, Unit>? wipeResult;
  int deleteCalls = 0;
  int wipeCalls = 0;

  /// Cosa c'era ancora nella sessione quando il profilo è stato cancellato.
  FakeSessionRepository? sessionsToObserve;
  OnlineSession? sessionAtDelete;

  @override
  Future<Either<Failure, Profile?>> getProfile() async =>
      getResult ?? Right(saved);

  @override
  Future<Either<Failure, Unit>> saveProfile(Profile profile) async {
    saved = profile;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> deleteProfile() async {
    deleteCalls++;
    sessionAtDelete = sessionsToObserve?.current;
    saved = null;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, bool>> isFirstLaunchAfterInstall() async =>
      Right(!hasInstallMarker);

  @override
  Future<Either<Failure, Unit>> markFirstLaunchDone() async {
    hasInstallMarker = true;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> deleteAllSecureData() async {
    wipeCalls++;
    final result = wipeResult ?? const Right(unit);
    if (result.isRight()) saved = null;
    return result;
  }
}

/// Rilevamento volto finto: risponde [result] e ricorda cosa ha controllato.
class FakeFaceDetectionRepository implements FaceDetectionRepository {
  FakeFaceDetectionRepository({this.result = const Right(true)});

  Either<Failure, bool> result;
  final checked = <Uint8List>[];

  @override
  Future<Either<Failure, bool>> containsFace(Uint8List imageBytes) async {
    checked.add(imageBytes);
    return result;
  }
}
