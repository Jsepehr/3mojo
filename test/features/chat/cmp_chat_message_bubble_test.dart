import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/chat/domain/entities/chat_message.dart';
import 'package:threemojo_app/features/chat/presentation/widgets/cmp_chat_message_bubble.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('shows the message text and a time next to it', (tester) async {
    final message = ChatMessage(
      id: '1',
      isMine: true,
      text: 'Ciao!',
      sentAt: DateTime(2026, 1, 1, 9, 5),
    );

    await tester.pumpWidget(_wrap(CmpChatMessageBubble(message: message)));

    expect(find.textContaining('Ciao!'), findsOneWidget);
    expect(find.textContaining('09:05'), findsOneWidget);
  });

  testWidgets('aligns mine to the right and others to the left', (
    tester,
  ) async {
    final mine = ChatMessage(
      id: '1',
      isMine: true,
      text: 'a',
      sentAt: DateTime(2026, 1, 1),
    );
    final theirs = ChatMessage(
      id: '2',
      isMine: false,
      text: 'b',
      sentAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            CmpChatMessageBubble(message: mine),
            CmpChatMessageBubble(message: theirs),
          ],
        ),
      ),
    );

    final mineAlign = tester.widget<Align>(
      find.ancestor(of: find.textContaining('a'), matching: find.byType(Align)),
    );
    final theirsAlign = tester.widget<Align>(
      find.ancestor(of: find.textContaining('b'), matching: find.byType(Align)),
    );

    expect(mineAlign.alignment, AlignmentDirectional.centerEnd);
    expect(theirsAlign.alignment, AlignmentDirectional.centerStart);
  });

  testWidgets('in RTL (Arabic) mine sits on the left and others on the '
      'right; in LTR the opposite', (tester) async {
    final mine = ChatMessage(
      id: '1',
      isMine: true,
      text: 'a',
      sentAt: DateTime(2026, 1, 1),
    );
    final theirs = ChatMessage(
      id: '2',
      isMine: false,
      text: 'b',
      sentAt: DateTime(2026, 1, 1),
    );

    for (final (locale, mineOnRight) in [
      (const Locale('en'), true),
      (const Locale('ar'), false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                CmpChatMessageBubble(message: mine),
                CmpChatMessageBubble(message: theirs),
              ],
            ),
          ),
        ),
      );
      final mineX = tester.getCenter(find.textContaining('a')).dx;
      final theirsX = tester.getCenter(find.textContaining('b')).dx;
      expect(mineX > theirsX, mineOnRight, reason: '$locale');
    }
  });
}
