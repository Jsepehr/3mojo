import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/session/domain/usecases/check_connection_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_connection_status_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_server_session_restarts_usecase.dart';
import 'package:threemojo_app/features/session/presentation/providers/pro_connection.dart';

import '../../support/fake_repositories.dart';

void main() {
  testWidgets('back in the foreground the connection is checked; going to '
      'the background leaves it alone', (tester) async {
    final connection = FakeConnectionRepository();
    final proConnection = ProConnection(
      watchConnectionStatusUseCase: WatchConnectionStatusUseCase(connection),
      watchServerSessionRestartsUseCase: WatchServerSessionRestartsUseCase(
        connection,
      ),
      checkConnectionUseCase: CheckConnectionUseCase(connection),
    );
    addTearDown(proConnection.dispose);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(connection.checkCalls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(connection.checkCalls, 1);
  });
}
