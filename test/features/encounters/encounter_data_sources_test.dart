import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/encounters/data/datasources/encounter_remote_data_source.dart';
import 'package:threemojo_app/features/encounters/data/datasources/encounter_remote_data_source_fake_impl.dart';
import 'package:threemojo_app/features/encounters/data/datasources/encounter_remote_data_source_impl.dart';
import 'package:threemojo_app/features/encounters/data/repositories/encounter_repository_impl.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_proposal.dart';

import '../../support/fake_realtime_socket.dart';

const _secret = '0f6a2c7e-1d3b-4c55-9a8e-7b2f4e6d8c10';

void main() {
  group('EncounterRemoteDataSourceImpl', () {
    late FakeRealtimeServer server;
    late EncounterRepositoryImpl repository;

    setUp(() {
      server = FakeRealtimeServer();
      repository = EncounterRepositoryImpl(
        EncounterRemoteDataSourceImpl(connection: server.connection),
      );
    });

    tearDown(() => server.connection.disconnect());

    test('a request that cannot leave is a ConnectionFailure', () async {
      repository.watchRequests(_secret).listen((_) {});
      await pumpEvents();

      final result = repository.sendRequest(
        otherPersonId: 'p',
        proposal: EncounterProposal.sayHi,
      );

      expect(result.getLeft().toNullable(), isA<ConnectionFailure>());
    });

    test('once connected, actions use the per-viewer person id', () async {
      repository.watchRequests(_secret).listen((_) {});
      await pumpEvents();
      server.last.welcome();
      await pumpEvents();

      expect(
        repository
            .sendRequest(otherPersonId: 'p', proposal: EncounterProposal.drink)
            .isRight(),
        isTrue,
      );
      // Sul filo solo il codice stabile della proposta, mai una frase.
      expect(server.last.sent.last, {
        'type': 'sendEncounterRequest',
        'toPersonId': 'p',
        'proposal': 'drink',
      });
    });

    test('an unknown status skips that request only', () async {
      final snapshots = <EncounterSnapshotModel>[];
      EncounterRemoteDataSourceImpl(
        connection: server.connection,
      ).watchRequests(_secret).listen(snapshots.add);
      await pumpEvents();
      server.last
        ..welcome()
        ..serverSends({
          'type': 'encounters',
          'incoming': [
            {'id': 'r1', 'otherPersonId': 'p', 'status': 'pending'},
            {'id': 'r2', 'otherPersonId': 'q', 'status': 'snoozed'},
          ],
          'outgoing': [],
        });
      await pumpEvents();

      expect(snapshots.single.incoming.map((r) => r.id), ['r1']);
    });

    test('both sides of the snapshot carry the proposal; an unknown code '
        'becomes getToKnow instead of failing the snapshot', () async {
      final snapshots = <EncounterSnapshotModel>[];
      EncounterRemoteDataSourceImpl(
        connection: server.connection,
      ).watchRequests(_secret).listen(snapshots.add);
      await pumpEvents();
      server.last
        ..welcome()
        ..serverSends({
          'type': 'encounters',
          'incoming': [
            {
              'id': 'r1',
              'otherPersonId': 'p',
              'status': 'pending',
              'proposal': 'drink',
            },
            {
              'id': 'r2',
              'otherPersonId': 'q',
              'status': 'pending',
              'proposal': 'somethingNew',
            },
          ],
          'outgoing': [
            {
              'id': 'r3',
              'otherPersonId': 's',
              'status': 'declined',
              'proposal': 'sayHi',
            },
          ],
        });
      await pumpEvents();

      final snapshot = snapshots.single;
      expect(snapshot.incoming.map((r) => r.proposal), [
        EncounterProposal.drink,
        EncounterProposal.getToKnow,
      ]);
      expect(snapshot.outgoing.single.proposal, EncounterProposal.sayHi);
    });
  });

  group('EncounterRemoteDataSourceImpl selfies', () {
    late FakeRealtimeServer server;

    setUp(() => server = FakeRealtimeServer());
    tearDown(() => server.connection.disconnect());

    test('the selfie sent once by the server is kept for later snapshots of '
        'the same request, and dropped when the request is over', () async {
      final selfie = base64Encode([0xFF, 0xD8, 0x01, 0xFF, 0xD9]);
      final snapshots = <EncounterSnapshotModel>[];
      final dataSource = EncounterRemoteDataSourceImpl(
        connection: server.connection,
      );
      dataSource.watchRequests(_secret).listen(snapshots.add);
      await pumpEvents();
      server.last
        ..welcome()
        ..serverSends({
          'type': 'encounters',
          'incoming': [
            {
              'id': 'r1',
              'otherPersonId': 'p',
              'status': 'pending',
              'otherSelfieBase64': selfie,
            },
          ],
          'outgoing': [],
        })
        // Lo snapshot dopo: niente selfie (il server non lo ripete).
        ..serverSends({
          'type': 'encounters',
          'incoming': [
            {'id': 'r1', 'otherPersonId': 'p', 'status': 'accepted'},
          ],
          'outgoing': [],
        })
        ..serverSends({
          'type': 'encounters',
          'incoming': [
            {'id': 'r1', 'otherPersonId': 'p', 'status': 'ended'},
          ],
          'outgoing': [],
        })
        // Uno stato vivo "rinato" con lo stesso id non ritrova il vecchio
        // selfie: è stato dimenticato con la fine della richiesta.
        ..serverSends({
          'type': 'encounters',
          'incoming': [
            {'id': 'r1', 'otherPersonId': 'p', 'status': 'pending'},
          ],
          'outgoing': [],
        });
      await pumpEvents();

      final first = snapshots[0].incoming.single.otherSelfieBytes;
      expect(first, base64Decode(selfie));
      expect(snapshots[1].incoming.single.status.name, 'accepted');
      expect(snapshots[1].incoming.single.otherSelfieBytes, same(first));
      expect(snapshots[2].incoming.single.otherSelfieBytes, isNull);
      expect(snapshots[3].incoming.single.otherSelfieBytes, isNull);
    });

    test('the photo cache holds at least as many selfies as requests can '
        'carry at once (20 incoming + 5 outgoing pending)', () {
      expect(
        EncounterRemoteDataSourceImpl.maxRequestsWithSelfie,
        greaterThanOrEqualTo(25),
      );
    });
  });

  group('EncounterRemoteDataSourceFakeImpl', () {
    test('a new session, or a reset, starts from a clean state and closes '
        'the old stream', () async {
      final fake = EncounterRemoteDataSourceFakeImpl();
      var firstDone = false;
      fake
          .watchRequests('session-1')
          .listen((_) {}, onDone: () => firstDone = true);
      fake.sendRequest(
        otherPersonId: 'p',
        proposal: EncounterProposal.fallback,
      );

      final snapshots = <EncounterSnapshotModel>[];
      fake.watchRequests('session-2').listen(snapshots.add);
      await pumpEvents();

      expect(firstDone, isTrue);
      expect(snapshots.last.outgoing, isEmpty);

      var secondDone = false;
      fake
          .watchRequests('session-2')
          .listen((_) {}, onDone: () => secondDone = true);
      await fake.reset();
      expect(secondDone, isTrue);
    });

    test(
      'refuses a second request to the same person, like the server',
      () async {
        final fake = EncounterRemoteDataSourceFakeImpl();
        final snapshots = <EncounterSnapshotModel>[];
        fake.watchRequests('s').listen(snapshots.add);

        fake
          ..sendRequest(otherPersonId: 'p', proposal: EncounterProposal.chat)
          ..sendRequest(otherPersonId: 'p', proposal: EncounterProposal.chat);
        await pumpEvents();

        expect(snapshots.last.outgoing, hasLength(1));
        await fake.reset();
      },
    );

    test('an outgoing request keeps the chosen proposal', () async {
      final fake = EncounterRemoteDataSourceFakeImpl();
      final snapshots = <EncounterSnapshotModel>[];
      fake
        ..watchRequests('s').listen(snapshots.add)
        ..sendRequest(otherPersonId: 'p', proposal: EncounterProposal.drink);
      await pumpEvents();

      expect(snapshots.last.outgoing.single.proposal, EncounterProposal.drink);
      await fake.reset();
    });
  });
}
