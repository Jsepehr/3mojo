import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:threemojo_app/core/errors/exceptions.dart';
import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/chat/data/datasources/chat_remote_data_source_impl.dart';
import 'package:threemojo_app/features/chat/data/models/chat_message_model.dart';
import 'package:threemojo_app/features/chat/data/repositories/chat_repository_impl.dart';

import '../../support/fake_realtime_socket.dart';

const _secret = '0f6a2c7e-1d3b-4c55-9a8e-7b2f4e6d8c10';

void main() {
  late FakeRealtimeServer server;
  late ChatRemoteDataSourceImpl dataSource;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = FakeRealtimeServer();
    dataSource = ChatRemoteDataSourceImpl(connection: server.connection);
  });

  tearDown(() => server.connection.disconnect());

  void incoming(String from, String text) => server.last.serverSends({
    'type': 'chatMessage',
    'fromPersonId': from,
    'text': text,
    'sentAt': '2026-01-01T10:00:00.000Z',
  });

  test('an incoming message is stored once, whatever the number of '
      'listeners', () async {
    final first = <ChatMessageModel>[];
    final second = <ChatMessageModel>[];
    dataSource
        .watchIncomingMessages(sessionId: _secret, otherPersonId: 'p')
        .listen(first.add);
    dataSource
        .watchIncomingMessages(sessionId: _secret, otherPersonId: 'p')
        .listen(second.add);
    await pumpEvents();
    server.last.welcome();
    incoming('p', 'ciao');
    await pumpEvents();

    expect(first.single.text, 'ciao');
    expect(second.single.text, 'ciao');
    expect(await dataSource.getMessages('conv-p'), hasLength(1));
  });

  test('deleting a conversation really empties it, and later messages from '
      'that person are dropped', () async {
    dataSource.watchIncomingMessages(sessionId: _secret, otherPersonId: 'p');
    await pumpEvents();
    server.last.welcome();
    incoming('p', 'uno');
    await pumpEvents();

    await dataSource.deleteConversation('p');
    incoming('p', 'tardivo');
    await pumpEvents();

    expect(await dataSource.getMessages('conv-p'), isEmpty);
  });

  test('a message that cannot leave is not stored and becomes a '
      'ConnectionFailure', () async {
    dataSource.watchIncomingMessages(sessionId: _secret, otherPersonId: 'p');
    await pumpEvents(); // no welcome yet: not ready

    expect(
      () => dataSource.appendMessage(
        conversationId: 'conv-p',
        otherPersonId: 'p',
        text: 'ciao',
      ),
      throwsA(isA<ServerException>()),
    );
    final result = await ChatRepositoryImpl(
      dataSource,
    ).appendMessage(conversationId: 'conv-p', otherPersonId: 'p', text: 'ciao');
    expect(result.getLeft().toNullable(), isA<ConnectionFailure>());
    expect(await dataSource.getMessages('conv-p'), isEmpty);
  });

  test('a sent message carries its id as clientMessageId', () async {
    dataSource.watchIncomingMessages(sessionId: _secret, otherPersonId: 'p');
    await pumpEvents();
    server.last.welcome();
    await pumpEvents();

    final message = await dataSource.appendMessage(
      conversationId: 'conv-p',
      otherPersonId: 'p',
      text: 'ciao',
    );

    expect(server.last.sent.last, {
      'type': 'chatMessage',
      'toPersonId': 'p',
      'text': 'ciao',
      'clientMessageId': message.id,
    });
  });

  test('a new session starts from an empty history', () async {
    dataSource.watchIncomingMessages(sessionId: _secret, otherPersonId: 'p');
    await pumpEvents();
    server.last.welcome();
    incoming('p', 'vecchio');
    await pumpEvents();

    dataSource.watchIncomingMessages(
      sessionId: '9b1e5d3c-7a2f-4e60-8c4d-2f6a8b0c1e3d',
      otherPersonId: 'p',
    );
    await pumpEvents();

    expect(await dataSource.getMessages('conv-p'), isEmpty);
  });

  test('a message that arrives before the match page opens is not lost: '
      'receiving started with the session keeps it in the history', () async {
    dataSource.startReceiving(_secret);
    await pumpEvents();
    server.last.welcome();
    // Il partner scrive subito dopo il match, la pagina non è ancora aperta.
    incoming('p', 'eccomi');
    await pumpEvents();

    final conversation = await dataSource.getOrCreateConversation(
      otherPersonId: 'p',
    );
    final history = await dataSource.getMessages(conversation.id);
    expect(history.single.text, 'eccomi');

    final later = <ChatMessageModel>[];
    dataSource
        .watchIncomingMessages(sessionId: _secret, otherPersonId: 'p')
        .listen(later.add);
    incoming('p', 'ci sei?');
    await pumpEvents();
    expect(later.single.text, 'ci sei?');
    expect(await dataSource.getMessages(conversation.id), hasLength(2));
  });
}
