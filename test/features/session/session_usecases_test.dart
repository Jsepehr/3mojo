import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/usecases/usecase.dart';
import 'package:threemojo_app/features/session/domain/entities/server_handshake.dart';
import 'package:threemojo_app/features/session/domain/usecases/end_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/session_teardown_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_server_session_restarts_usecase.dart';

import '../../support/fake_repositories.dart';

class _RecordingStep implements SessionTeardownUseCase {
  _RecordingStep(this.sessions, {this.neverCompletes = false});

  final FakeSessionRepository sessions;
  final bool neverCompletes;
  final calls = <String>[];
  bool sessionWasAlreadyEnded = false;

  @override
  Future<Either<Failure, Unit>> call(String endingSessionId) {
    calls.add(endingSessionId);
    sessionWasAlreadyEnded = sessions.current == null;
    if (neverCompletes) return Completer<Either<Failure, Unit>>().future;
    return Future.value(const Right(unit));
  }
}

void main() {
  group('EndSessionUseCase', () {
    test('ends the local session first, then runs every teardown step with '
        'the ending session id', () async {
      final sessions = FakeSessionRepository(current: testSession('s1'));
      final step = _RecordingStep(sessions);

      final result = await EndSessionUseCase(
        repository: sessions,
        teardownSteps: [step],
      )(const NoParams());

      expect(result.isRight(), isTrue);
      expect(step.calls, ['s1']);
      expect(step.sessionWasAlreadyEnded, isTrue);
    });

    test('a stuck step never blocks End', () {
      fakeAsync((async) {
        final sessions = FakeSessionRepository(current: testSession('s1'));
        Either<Failure, Unit>? result;

        EndSessionUseCase(
          repository: sessions,
          teardownSteps: [_RecordingStep(sessions, neverCompletes: true)],
        )(const NoParams()).then((value) => result = value);

        async.elapse(const Duration(seconds: 2));
        expect(result, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(result?.isRight(), isTrue);
        expect(sessions.current, isNull);
      });
    });
  });

  group('WatchServerSessionRestartsUseCase', () {
    test(
      'only a non-resumed welcome after the first one is a restart',
      () async {
        final connection = FakeConnectionRepository();
        final restarts = <Unit>[];
        WatchServerSessionRestartsUseCase(connection)().listen(restarts.add);

        connection.handshakes
          ..add(const ServerHandshake(resumed: false, isFirstOfSession: true))
          ..add(const ServerHandshake(resumed: true, isFirstOfSession: false))
          ..add(const ServerHandshake(resumed: false, isFirstOfSession: false));
        await Future<void>.delayed(Duration.zero);

        expect(restarts, hasLength(1));
      },
    );
  });
}
