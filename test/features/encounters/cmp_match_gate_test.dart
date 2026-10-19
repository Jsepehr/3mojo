import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:threemojo_app/core/theme/app_theme.dart';
import 'package:threemojo_app/features/chat/domain/usecases/send_message_usecase.dart';
import 'package:threemojo_app/features/chat/presentation/providers/pro_chat.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/encounters/presentation/pages/ui_active_match.dart';
import 'package:threemojo_app/features/encounters/presentation/providers/pro_encounters.dart';
import 'package:threemojo_app/features/encounters/presentation/widgets/cmp_encounter_notice_listener.dart';
import 'package:threemojo_app/features/encounters/presentation/widgets/cmp_match_gate.dart';
import 'package:threemojo_app/features/session/domain/usecases/check_connection_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_connection_status_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_server_session_restarts_usecase.dart';
import 'package:threemojo_app/features/session/presentation/providers/pro_connection.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import '../../support/build_providers.dart';
import '../../support/fake_repositories.dart';

/// Snapshot consegnato, pagina spinta/tolta dal post-frame, animazione
/// della route conclusa.
Future<void> _pumpTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the other person ends the match: the page closes, the chat is '
      'forgotten and the user is told', (tester) async {
    final sessions = FakeSessionRepository(current: testSession('s1'));
    final encounters = FakeEncounterRepository();
    final chat = FakeChatRepository();
    final connection = FakeConnectionRepository();
    final proEncounters = buildProEncounters(
      sessions: sessions,
      encounters: encounters,
      chat: chat,
      connection: connection,
    );
    final proChat = buildProChat(sessions: sessions, chat: chat);
    final proConnection = ProConnection(
      watchConnectionStatusUseCase: WatchConnectionStatusUseCase(connection),
      watchServerSessionRestartsUseCase: WatchServerSessionRestartsUseCase(
        connection,
      ),
      checkConnectionUseCase: CheckConnectionUseCase(connection),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProEncounters>.value(value: proEncounters),
          ChangeNotifierProvider<ProChat>.value(value: proChat),
          ChangeNotifierProvider<ProConnection>.value(value: proConnection),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CmpEncounterNoticeListener(
            child: CmpMatchGate(child: Scaffold(body: Text('home'))),
          ),
        ),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pump();

    encounters.push((
      incoming: [
        testRequest('m1', EncounterRequestStatus.accepted, otherPersonId: 'p1'),
      ],
      outgoing: [],
    ));
    await _pumpTransition(tester);
    expect(find.byType(UiActiveMatch), findsOneWidget);
    expect(chat.opened, ['p1']);
    expect(chat.incoming.hasListener, isTrue);

    encounters.push((
      incoming: [
        testRequest('m1', EncounterRequestStatus.ended, otherPersonId: 'p1'),
      ],
      outgoing: [],
    ));
    await _pumpTransition(tester);

    expect(find.byType(UiActiveMatch), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(chat.deleted, contains('p1'));
    expect(chat.incoming.hasListener, isFalse);
    expect(find.text(l10n.match_ended_partner_left), findsOneWidget);

    // Smonta prima di liberare i provider.
    await tester.pumpWidget(const SizedBox());
    proEncounters.dispose();
    proChat.dispose();
    proConnection.dispose();
  });

  testWidgets('the partner ends the match while the "end this match?" '
      'dialog is open: the dialog goes away too', (tester) async {
    final sessions = FakeSessionRepository(current: testSession('s1'));
    final encounters = FakeEncounterRepository();
    final chat = FakeChatRepository();
    final connection = FakeConnectionRepository();
    final proEncounters = buildProEncounters(
      sessions: sessions,
      encounters: encounters,
      chat: chat,
      connection: connection,
    );
    final proChat = buildProChat(sessions: sessions, chat: chat);
    final proConnection = ProConnection(
      watchConnectionStatusUseCase: WatchConnectionStatusUseCase(connection),
      watchServerSessionRestartsUseCase: WatchServerSessionRestartsUseCase(
        connection,
      ),
      checkConnectionUseCase: CheckConnectionUseCase(connection),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProEncounters>.value(value: proEncounters),
          ChangeNotifierProvider<ProChat>.value(value: proChat),
          ChangeNotifierProvider<ProConnection>.value(value: proConnection),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CmpMatchGate(child: Scaffold(body: Text('home'))),
        ),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pump();

    encounters.push((
      incoming: [
        testRequest('m1', EncounterRequestStatus.accepted, otherPersonId: 'p1'),
      ],
      outgoing: [],
    ));
    await _pumpTransition(tester);
    await tester.tap(find.text(l10n.end_match));
    await _pumpTransition(tester);
    expect(find.text(l10n.end_this_match), findsOneWidget);

    encounters.push((
      incoming: [
        testRequest('m1', EncounterRequestStatus.ended, otherPersonId: 'p1'),
      ],
      outgoing: [],
    ));
    await _pumpTransition(tester);

    expect(find.text(l10n.end_this_match), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(UiActiveMatch), findsNothing);
    expect(find.text('home'), findsOneWidget);
    // Il dialogo chiuso così non vale come "sì, termina".
    expect(encounters.endedMatches, isEmpty);

    await tester.pumpWidget(const SizedBox());
    proEncounters.dispose();
    proChat.dispose();
    proConnection.dispose();
  });

  testWidgets('a message over the limit does not enter the chat: the text '
      'goes back into the field and the user is told', (tester) async {
    final sessions = FakeSessionRepository(current: testSession('s1'));
    final encounters = FakeEncounterRepository();
    final chat = FakeChatRepository();
    final proEncounters = buildProEncounters(
      sessions: sessions,
      encounters: encounters,
      chat: chat,
    );
    final proChat = buildProChat(sessions: sessions, chat: chat);
    final connection = FakeConnectionRepository();
    final proConnection = ProConnection(
      watchConnectionStatusUseCase: WatchConnectionStatusUseCase(connection),
      watchServerSessionRestartsUseCase: WatchServerSessionRestartsUseCase(
        connection,
      ),
      checkConnectionUseCase: CheckConnectionUseCase(connection),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProEncounters>.value(value: proEncounters),
          ChangeNotifierProvider<ProChat>.value(value: proChat),
          ChangeNotifierProvider<ProConnection>.value(value: proConnection),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CmpMatchGate(child: Scaffold(body: Text('home'))),
        ),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pump();
    encounters.push((
      incoming: [
        testRequest('m1', EncounterRequestStatus.accepted, otherPersonId: 'p1'),
      ],
      outgoing: [],
    ));
    await _pumpTransition(tester);

    // Emoji: per il campo sono pochi caratteri visibili, per il server
    // (unità UTF-16) oltre il limite.
    final tooLong = '😀' * (SendMessageUseCase.maxTextLength ~/ 2 + 1);
    await tester.enterText(find.byType(TextField), tooLong);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump();

    expect(proChat.messages, isEmpty);
    expect(
      find.text(l10n.chat_message_too_long(SendMessageUseCase.maxTextLength)),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      tooLong,
    );

    await tester.pumpWidget(const SizedBox());
    proEncounters.dispose();
    proChat.dispose();
    proConnection.dispose();
  });
}
