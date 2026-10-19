import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:threemojo_app/core/errors/exceptions.dart';
import 'package:threemojo_app/core/unlock/unlock_token_store.dart';
import 'package:threemojo_app/features/nearby/data/datasources/nearby_remote_data_source_impl.dart';
import 'package:threemojo_app/features/nearby/data/models/nearby_person_model.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';

import '../../support/fake_realtime_socket.dart';

const _secret = '0f6a2c7e-1d3b-4c55-9a8e-7b2f4e6d8c10';

/// Nessun token di sblocco, nessun `shared_preferences`.
class _NoUnlockTokenStore implements UnlockTokenStore {
  final _changes = StreamController<String?>.broadcast();

  @override
  Stream<String?> get changes => _changes.stream;

  @override
  Future<String?> read() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _profile = Profile(
  gender: Gender.female,
  lookingFor: {Gender.male},
  isAdultConfirmed: true,
  sensitiveDataConsent: true,
  languages: ['it'],
);

void main() {
  late FakeRealtimeServer server;
  late NearbyRemoteDataSourceImpl dataSource;
  final selfie = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

  setUp(() {
    server = FakeRealtimeServer();
    dataSource = NearbyRemoteDataSourceImpl(
      connection: server.connection,
      unlockTokenStore: _NoUnlockTokenStore(),
      prepareSelfie: (bytes) async => bytes,
    );
  });

  tearDown(() => dataSource.disconnect());

  Stream<List<NearbyPersonModel>> connect() => dataSource.connect(
    sessionId: _secret,
    latitude: 45,
    longitude: 9,
    profile: _profile,
    intent: MeetIntent.chat,
    selfieBytes: selfie,
  );

  Iterable<Map<String, dynamic>> presences(FakeRealtimeSocket socket) =>
      socket.sent.where((m) => m['type'] == 'presence');

  test('the full presence (profile + selfie) leaves only after welcome, '
      'later updates carry just the position', () async {
    connect();
    dataSource.updatePosition(latitude: 45.0001, longitude: 9);
    await pumpEvents();
    expect(presences(server.last), isEmpty);

    server.last.welcome();
    await pumpEvents();
    final full = presences(server.last).single;
    expect(full['lat'], 45.0001);
    expect(full['gender'], 'female');
    expect(full['intent'], 'chat');
    expect(full['selfieBase64'], base64Encode(selfie));

    dataSource.updatePosition(latitude: 45.0002, longitude: 9);
    final update = presences(server.last).last;
    expect(update['lat'], 45.0002);
    expect(update.containsKey('selfieBase64'), isFalse);
  });

  test('after a reconnection the full presence is sent again', () async {
    connect().listen((_) {}, onError: (_) {});
    await pumpEvents();
    server.last.welcome();
    await pumpEvents();

    await server.last.serverCloses();
    await pumpEvents();
    server.last.welcome();
    await pumpEvents();

    expect(presences(server.last).single['selfieBase64'], isNotNull);
  });

  test('a resumed session does not get the selfie again once the server '
      'has it; a forgotten one does', () async {
    connect().listen((_) {}, onError: (_) {});
    await pumpEvents();
    server.last.welcome();
    await pumpEvents();
    // La prima lista dopo la presenza dice che il server l'ha accettata.
    server.last.serverSends({'type': 'nearby', 'people': []});
    await pumpEvents();

    await server.last.serverCloses();
    await pumpEvents();
    server.last.welcome(resumed: true);
    await pumpEvents();

    final resumed = presences(server.last).single;
    expect(resumed.containsKey('selfieBase64'), isFalse);
    expect(resumed['gender'], 'female');

    await server.last.serverCloses();
    await pumpEvents();
    server.last.welcome();
    await pumpEvents();

    expect(presences(server.last).single['selfieBase64'], isNotNull);
  });

  test('resumed before the server ever confirmed the presence: the selfie '
      'is sent again (it may never have arrived)', () async {
    connect().listen((_) {}, onError: (_) {});
    await pumpEvents();
    server.last.welcome();
    await pumpEvents();

    await server.last.serverCloses();
    await pumpEvents();
    server.last.welcome(resumed: true);
    await pumpEvents();

    expect(presences(server.last).single['selfieBase64'], isNotNull);
  });

  test('a selfie that cannot be prepared is never sent as it is: no presence '
      'leaves and the stream reports it', () async {
    final failing = NearbyRemoteDataSourceImpl(
      connection: server.connection,
      unlockTokenStore: _NoUnlockTokenStore(),
      prepareSelfie: (_) async => throw const FormatException('broken'),
    );
    addTearDown(failing.disconnect);
    final errors = <Object>[];
    final subscription = failing
        .connect(
          sessionId: _secret,
          latitude: 45,
          longitude: 9,
          profile: _profile,
          selfieBytes: selfie,
        )
        .listen((_) {}, onError: errors.add);
    await pumpEvents();
    server.last.welcome();
    await pumpEvents();
    failing.updatePosition(latitude: 45.001, longitude: 9);

    expect(errors.single, isA<SelfiePreparationException>());
    expect(presences(server.last), isEmpty);

    // Un Riprova (nuovo ascolto, stessa sessione) lo racconta di nuovo.
    final again = <Object>[];
    final retry = failing
        .connect(
          sessionId: _secret,
          latitude: 45,
          longitude: 9,
          profile: _profile,
          selfieBytes: selfie,
        )
        .listen((_) {}, onError: again.add);
    await pumpEvents();
    expect(again.single, isA<SelfiePreparationException>());
    expect(presences(server.last), isEmpty);
    await subscription.cancel();
    await retry.cancel();
  });

  test('a selfie still too big after preparation is not sent either', () async {
    final tooBig = NearbyRemoteDataSourceImpl(
      connection: server.connection,
      unlockTokenStore: _NoUnlockTokenStore(),
      prepareSelfie: (_) async => Uint8List(maxUploadSelfieBytes + 1),
    );
    addTearDown(tooBig.disconnect);
    final errors = <Object>[];
    final subscription = tooBig
        .connect(
          sessionId: _secret,
          latitude: 45,
          longitude: 9,
          profile: _profile,
          selfieBytes: selfie,
        )
        .listen((_) {}, onError: errors.add);
    await pumpEvents();
    server.last.welcome();
    await pumpEvents();

    expect(errors.single, isA<SelfiePreparationException>());
    expect(presences(server.last), isEmpty);
    await subscription.cancel();
  });

  test('an undecodable file makes the preparation fail instead of passing '
      'through', () {
    expect(
      () => prepareSelfieForUpload(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  test('a person with an unknown value is skipped, not the whole list; a '
      'locked one has no photo', () async {
    final lists = <List<NearbyPersonModel>>[];
    connect().listen(lists.add);
    await pumpEvents();
    server.last
      ..welcome()
      ..serverSends({
        'type': 'nearby',
        'people': [
          {'personId': 'p1', 'meetingChance': 'high', 'locked': false},
          {'personId': 'p2', 'meetingChance': 'ultra', 'locked': false},
          {
            'personId': 'p3',
            'meetingChance': 'low',
            'locked': true,
            'selfieBase64': base64Encode(selfie),
          },
          'garbage',
        ],
      });
    await pumpEvents();

    final people = lists.single;
    expect(people.map((p) => p.id), ['p1', 'p3']);
    expect(people.first.meetingChance, MeetingChance.high);
    expect(people.last.isLocked, isTrue);
    expect(people.last.photoBytes, isNull);
  });

  test('after disconnect nothing is sent any more', () async {
    connect();
    await pumpEvents();
    final socket = server.last..welcome();
    await pumpEvents();

    await dataSource.disconnect();
    final sentBefore = socket.sent.length;
    dataSource.updatePosition(latitude: 1, longitude: 1);

    expect(socket.sentTypes, contains('end'));
    expect(socket.sent, hasLength(sentBefore));
  });

  test('the selfie is resized and stripped of its metadata before leaving '
      'the phone', () {
    final photo = img.Image(width: 1600, height: 1200);
    photo.exif.imageIfd['Make'] = img.IfdValueAscii('PhoneMaker');
    final original = Uint8List.fromList(img.encodeJpg(photo));
    expect(img.decodeJpg(original)!.exif.isEmpty, isFalse);

    final prepared = img.decodeJpg(prepareSelfieForUpload(original))!;

    expect(prepared.width, 640);
    expect(prepared.height, 480);
    expect(prepared.exif.isEmpty, isTrue);
  });

  test('a selfie rejected by the server becomes an error on the stream, and '
      'no presence leaves any more for that session', () async {
    final errors = <Object>[];
    final subscription = connect().listen((_) {}, onError: errors.add);
    await pumpEvents();
    final socket = server.last..welcome();
    await pumpEvents();
    expect(presences(socket), hasLength(1));

    socket.serverSends({
      'type': 'rejected',
      'action': 'presence',
      'reason': 'invalidSelfie',
    });
    await pumpEvents();
    dataSource.updatePosition(latitude: 45.001, longitude: 9);
    // Anche un Riprova (stessa sessione) non rimanda il selfie rifiutato.
    connect();
    await pumpEvents();

    expect(errors.single, isA<SelfieRejectedException>());
    expect(presences(socket), hasLength(1));
    await subscription.cancel();
  });

  test('"rateLimited" from the server becomes its own error, not a generic '
      'connection drop', () async {
    final errors = <Object>[];
    final subscription = connect().listen((_) {}, onError: errors.add);
    await pumpEvents();

    server.last.serverSends({'type': 'error', 'code': 'rateLimited'});
    await pumpEvents();

    expect(errors.first, isA<RateLimitedException>());
    await subscription.cancel();
  });

  test('other rejections (e.g. a request) are not presence errors', () async {
    final errors = <Object>[];
    final subscription = connect().listen((_) {}, onError: errors.add);
    await pumpEvents();
    server.last
      ..welcome()
      ..serverSends({
        'type': 'rejected',
        'action': 'sendEncounterRequest',
        'reason': 'notNearby',
      });
    await pumpEvents();

    expect(errors, isEmpty);
    await subscription.cancel();
  });
}
