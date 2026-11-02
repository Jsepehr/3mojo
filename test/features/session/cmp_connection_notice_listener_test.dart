import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:threemojo_app/features/session/domain/entities/session_closure_reason.dart';
import 'package:threemojo_app/features/session/domain/usecases/check_connection_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_connection_status_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_server_session_restarts_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_closed_by_server_usecase.dart';
import 'package:threemojo_app/features/session/presentation/providers/pro_connection.dart';
import 'package:threemojo_app/features/session/presentation/widgets/cmp_connection_notice_listener.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import '../../support/fake_repositories.dart';

void main() {
  test('a closure reason from the wire: serverRestart, anything else is '
      '"reports" (the only one old servers sent)', () {
    expect(
      SessionClosureReason.fromWire('serverRestart'),
      SessionClosureReason.serverRestart,
    );
    expect(
      SessionClosureReason.fromWire('reports'),
      SessionClosureReason.reports,
    );
    expect(SessionClosureReason.fromWire('nope'), SessionClosureReason.reports);
    expect(SessionClosureReason.fromWire(null), SessionClosureReason.reports);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('[${locale.languageCode}] each closure reason has its own '
        'dialog text', (tester) async {
      final connection = FakeConnectionRepository();
      final proConnection = ProConnection(
        watchConnectionStatusUseCase: WatchConnectionStatusUseCase(connection),
        watchServerSessionRestartsUseCase: WatchServerSessionRestartsUseCase(
          connection,
        ),
        checkConnectionUseCase: CheckConnectionUseCase(connection),
        watchSessionClosedByServerUseCase: WatchSessionClosedByServerUseCase(
          connection,
        ),
      );
      addTearDown(proConnection.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<ProConnection>.value(
          value: proConnection,
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CmpConnectionNoticeListener(
              child: Scaffold(body: SizedBox()),
            ),
          ),
        ),
      );
      final l10n = await AppLocalizations.delegate.load(locale);

      connection.closures.add(SessionClosureReason.serverRestart);
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.session_closed_server_restart_title),
        findsOneWidget,
      );
      expect(
        find.text(l10n.session_closed_server_restart_body),
        findsOneWidget,
      );
      expect(find.text(l10n.session_closed_after_reports_body), findsNothing);
      await tester.tap(find.text(l10n.ok));
      await tester.pumpAndSettle();

      connection.closures.add(SessionClosureReason.reports);
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.session_closed_after_reports_title),
        findsOneWidget,
      );
      expect(find.text(l10n.session_closed_after_reports_body), findsOneWidget);
      expect(find.text(l10n.session_closed_server_restart_body), findsNothing);
      expect(
        l10n.session_closed_server_restart_body,
        isNot(l10n.session_closed_after_reports_body),
      );
    });
  }
}
