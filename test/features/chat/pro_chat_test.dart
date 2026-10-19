import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/chat/domain/entities/chat_message.dart';
import 'package:threemojo_app/features/chat/domain/usecases/send_message_usecase.dart';
import 'package:threemojo_app/features/chat/presentation/providers/pro_chat.dart';

import '../../support/build_providers.dart';
import '../../support/fake_repositories.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

ChatMessage _incoming(String text) => ChatMessage(
  id: 'in-$text',
  isMine: false,
  text: text,
  sentAt: DateTime(2026),
);

void main() {
  late FakeSessionRepository sessions;
  late FakeChatRepository chat;
  late ProChat proChat;

  setUp(() async {
    sessions = FakeSessionRepository(current: testSession('s1'));
    chat = FakeChatRepository();
    proChat = buildProChat(sessions: sessions, chat: chat);
    await proChat.open(otherPersonId: 'p1');
    await _settle();
  });

  tearDown(() => proChat.dispose());

  test('close() stops listening and empties the messages', () async {
    chat.incoming.add(Right(_incoming('ciao')));
    await _settle();
    expect(proChat.messages, hasLength(1));

    proChat.close();
    chat.incoming.add(Right(_incoming('ancora')));
    await _settle();

    expect(proChat.messages, isEmpty);
    expect(chat.incoming.hasListener, isFalse);
    expect(chat.undelivered.hasListener, isFalse);
  });

  test('closes by itself when the session ends', () async {
    chat.incoming.add(Right(_incoming('ciao')));
    await _settle();

    sessions.end();
    await _settle();

    expect(proChat.messages, isEmpty);
    expect(chat.incoming.hasListener, isFalse);
  });

  test('a message that cannot leave stays in the chat as "not sent"', () async {
    chat.appendResult = const Left(ConnectionFailure('offline'));

    await proChat.sendMessage('ci sei?');

    final message = proChat.messages.single;
    expect(message.text, 'ci sei?');
    expect(proChat.isUnsent(message), isTrue);
  });

  test('a message the server could not deliver becomes "not sent"', () async {
    await proChat.sendMessage('ciao');
    final message = proChat.messages.single;
    expect(proChat.isUnsent(message), isFalse);

    chat.undelivered.add(message.id);
    await _settle();

    expect(proChat.isUnsent(message), isTrue);
  });

  test('resend replaces the unsent message with the sent one', () async {
    chat.appendResult = const Left(ConnectionFailure('offline'));
    await proChat.sendMessage('ciao');
    final unsent = proChat.messages.single;

    chat.appendResult = null;
    await proChat.resend(unsent);

    final sent = proChat.messages.single;
    expect(sent.id, isNot(unsent.id));
    expect(proChat.isUnsent(sent), isFalse);
  });

  test('a late open result after close() does not refill the chat', () async {
    final opening = proChat.open(otherPersonId: 'p2');
    proChat.close();
    await opening;

    expect(proChat.messages, isEmpty);
    expect(proChat.isLoading, isFalse);
    expect(chat.incoming.hasListener, isFalse);
  });

  test(
    'a message over the limit never enters the chat (not even as "not '
    'sent", which would fail forever): the failure goes back to the UI',
    () async {
      final tooLong = 'a' * (SendMessageUseCase.maxTextLength + 1);

      final failure = await proChat.sendMessage(tooLong);

      expect(failure, const MessageTooLongFailure(1000));
      expect(proChat.messages, isEmpty);
    },
  );

  test(
    'receiving starts with the session, before any chat page is open',
    () async {
      final freshSessions = FakeSessionRepository();
      final freshChat = FakeChatRepository();
      final fresh = buildProChat(sessions: freshSessions, chat: freshChat);
      addTearDown(fresh.dispose);
      await _settle();
      expect(freshChat.startedReceiving, isEmpty);

      freshSessions.start(testSession('s2'));
      await _settle();

      expect(freshChat.startedReceiving, ['s2']);
      expect(freshChat.opened, isEmpty);
    },
  );

  group('SendMessageUseCase', () {
    test('accepts exactly the limit, counted in UTF-16 units like the '
        'server, after trimming', () async {
      final useCase = SendMessageUseCase(chat);
      SendMessageParams params(String text) => SendMessageParams(
        conversationId: 'conv-p1',
        otherPersonId: 'p1',
        text: text,
      );

      expect((await useCase(params('  ${'a' * 1000}  '))).isRight(), isTrue);
      expect(
        (await useCase(params('a' * 1001))).getLeft().toNullable(),
        isA<MessageTooLongFailure>(),
      );
      // 501 emoji = 1002 unità UTF-16: troppo lungo per il server.
      expect(
        (await useCase(params('😀' * 501))).getLeft().toNullable(),
        isA<MessageTooLongFailure>(),
      );
    });
  });
}
