import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:threemojo_app/core/errors/exceptions.dart';
import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/usecases/usecase.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/profile/data/models/profile_model.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/profile/domain/usecases/accept_terms_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/get_profile_usecase.dart';
import 'package:threemojo_app/features/profile/domain/usecases/save_profile_usecase.dart';
import 'package:threemojo_app/features/safety/data/datasources/blocked_people_local_data_source_impl.dart';
import 'package:threemojo_app/features/safety/data/datasources/safety_remote_data_source_fake_impl.dart';
import 'package:threemojo_app/features/safety/data/datasources/safety_remote_data_source_impl.dart';
import 'package:threemojo_app/features/safety/data/models/safety_rejection_model.dart';
import 'package:threemojo_app/features/safety/data/repositories/safety_repository_impl.dart';
import 'package:threemojo_app/features/safety/domain/entities/report_reason.dart';
import 'package:threemojo_app/features/safety/domain/entities/safety_rejection.dart';
import 'package:threemojo_app/features/safety/domain/usecases/block_person_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/clear_safety_session_state_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/hide_blocked_people_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/report_person_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/watch_blocked_people_usecase.dart';

import '../../support/fake_realtime_socket.dart';
import '../../support/fake_repositories.dart';
import '../../support/fake_safety.dart';

void main() {
  late FakeSafetyRemoteDataSource remote;
  late BlockedPeopleLocalDataSourceImpl local;
  late SafetyRepositoryImpl repository;
  late BlockPersonUseCase block;
  late ReportPersonUseCase report;

  setUp(() {
    remote = FakeSafetyRemoteDataSource();
    local = BlockedPeopleLocalDataSourceImpl();
    repository = SafetyRepositoryImpl(remote, local);
    block = BlockPersonUseCase(repository);
    report = ReportPersonUseCase(repository, block);
  });

  group('BlockPersonUseCase', () {
    test('once sent, the person is among the blocked of this session right '
        'away', () async {
      final seen = <Set<String>>[];
      final subscription = WatchBlockedPeopleUseCase(
        repository,
      )().listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      expect(block('p1'), const Right<Failure, Unit>(unit));
      await Future<void>.delayed(Duration.zero);

      expect(remote.blocked, ['p1']);
      expect(seen, [
        <String>{},
        {'p1'},
      ]);
      await subscription.cancel();
    });

    test('offline nothing leaves and nobody is hidden: the UI says "not '
        'sent"', () {
      remote.offline = true;

      final result = block('p1');

      expect(result.getLeft().toNullable(), isA<ConnectionFailure>());
      expect(local.blockedPersonIds, isEmpty);
    });

    test('an empty id is refused before touching the server', () {
      expect(block('').getLeft().toNullable(), isA<ValidationFailure>());
      expect(remote.blocked, isEmpty);
    });
  });

  group('ReportPersonUseCase', () {
    test('sends only the reason code, and the person is blocked too', () {
      final result = report(
        const ReportPersonParams(
          personId: 'p1',
          reason: ReportReason.harassment,
        ),
      );

      expect(result.isRight(), isTrue);
      expect(remote.reported, [('p1', ReportReason.harassment)]);
      expect(local.blockedPersonIds, {'p1'});
      expect(repository.reportsSentThisSession, 1);
    });

    test('past the limit of the session the report does not leave, but the '
        'person is still blocked', () {
      for (var i = 0; i < ReportPersonUseCase.maxReportsPerSession; i++) {
        expect(
          report(
            ReportPersonParams(personId: 'p$i', reason: ReportReason.spam),
          ).isRight(),
          isTrue,
        );
      }

      final result = report(
        const ReportPersonParams(personId: 'extra', reason: ReportReason.spam),
      );

      expect(
        result.getLeft().toNullable(),
        const TooManyReportsFailure(ReportPersonUseCase.maxReportsPerSession),
      );
      expect(remote.reported, hasLength(5));
      expect(remote.blocked, ['extra']);
      expect(local.blockedPersonIds, contains('extra'));
    });

    test('offline: not sent, not counted, nobody hidden', () {
      remote.offline = true;

      final result = report(
        const ReportPersonParams(personId: 'p1', reason: ReportReason.other),
      );

      expect(result.getLeft().toNullable(), isA<ConnectionFailure>());
      expect(repository.reportsSentThisSession, 0);
      expect(local.blockedPersonIds, isEmpty);
    });
  });

  test('End forgets the blocked and the report count of the session', () async {
    block('p1');
    report(
      const ReportPersonParams(personId: 'p2', reason: ReportReason.underage),
    );

    final result = await ClearSafetySessionStateUseCase(repository)('s1');

    expect(result.isRight(), isTrue);
    expect(local.blockedPersonIds, isEmpty);
    expect(repository.reportsSentThisSession, 0);
    expect(remote.resets, 1);
  });

  test('HideBlockedPeopleUseCase removes only what belongs to a blocked '
      'person, keeping the order', () {
    const hide = HideBlockedPeopleUseCase();
    final requests = [
      testRequest('r1', EncounterRequestStatus.pending, otherPersonId: 'a'),
      testRequest('r2', EncounterRequestStatus.pending, otherPersonId: 'b'),
      testRequest('r3', EncounterRequestStatus.pending, otherPersonId: 'c'),
    ];

    final visible = hide(
      requests,
      blockedPersonIds: {'b'},
      personIdOf: (request) => request.otherPersonId,
    );

    expect(visible.map((r) => r.id), ['r1', 'r3']);
    expect(
      hide(requests, blockedPersonIds: {}, personIdOf: (r) => r.otherPersonId),
      same(requests),
    );
  });

  group('SafetyRejectionModel', () {
    test('reads the rejections of block and report only', () {
      expect(
        SafetyRejectionModel.tryFromJson({
          'type': 'rejected',
          'action': 'report',
          'reason': 'tooManyReports',
          'personId': 'p1',
        }),
        const SafetyRejectionModel(
          action: SafetyAction.report,
          reason: SafetyRejectionReason.tooManyReports,
          personId: 'p1',
        ),
      );
      expect(
        SafetyRejectionModel.tryFromJson({
          'type': 'rejected',
          'action': 'block',
          'reason': 'somethingNew',
        })?.reason,
        SafetyRejectionReason.other,
      );
      expect(
        SafetyRejectionModel.tryFromJson({
          'type': 'rejected',
          'action': 'chatMessage',
          'reason': 'notDelivered',
        }),
        isNull,
      );
      expect(SafetyRejectionModel.tryFromJson({'type': 'nearby'}), isNull);
    });
  });

  group('SafetyRemoteDataSourceImpl', () {
    late FakeRealtimeServer server;

    setUp(() => server = FakeRealtimeServer());
    tearDown(() => server.connection.disconnect());

    test('block and report travel on the shared socket with the pseudonym '
        'and the reason code, never free text', () async {
      final dataSource = SafetyRemoteDataSourceImpl(
        connection: server.connection,
      );
      final rejections = <SafetyRejectionModel>[];
      dataSource
          .watchRejections('0f6a2c7e-1d3b-4c55-9a8e-7b2f4e6d8c10')
          .listen(rejections.add);
      await pumpEvents();

      expect(() => dataSource.block('p1'), throwsA(isA<ServerException>()));

      server.last.welcome();
      await pumpEvents();
      dataSource
        ..block('p1')
        ..report(personId: 'p2', reason: ReportReason.fakePhoto);
      server.last.serverSends({
        'type': 'rejected',
        'action': 'block',
        'reason': 'unknownPerson',
        'personId': 'p1',
      });
      await pumpEvents();

      expect(server.last.sent.skip(1), [
        {'type': 'block', 'personId': 'p1'},
        {'type': 'report', 'personId': 'p2', 'reason': 'fakePhoto'},
      ]);
      expect(rejections.single.reason, SafetyRejectionReason.unknownPerson);
    });
  });

  test(
    'the fake data source refuses the report past the server limit',
    () async {
      final fake = SafetyRemoteDataSourceFakeImpl();
      final rejections = <SafetyRejectionModel>[];
      fake.watchRejections('s').listen(rejections.add);

      for (
        var i = 0;
        i <= SafetyRemoteDataSourceFakeImpl.maxReportsPerSession;
        i++
      ) {
        fake.report(personId: 'p$i', reason: ReportReason.spam);
      }
      await Future<void>.delayed(Duration.zero);

      expect(rejections.single.reason, SafetyRejectionReason.tooManyReports);
      expect(
        SafetyRemoteDataSourceFakeImpl.maxReportsPerSession,
        ReportPersonUseCase.maxReportsPerSession,
      );
    },
  );

  group('terms of use on the profile', () {
    test('a profile saved before the terms existed reads as not accepted, '
        'and the accepted version survives the JSON round trip', () {
      final old = ProfileModel.fromJson({
        'gender': 'male',
        'lookingFor': ['female'],
        'isAdultConfirmed': true,
        'sensitiveDataConsent': true,
        'defaultIntent': null,
        'languages': <String>[],
        'showGender': false,
      });
      expect(old.acceptedTermsVersion, 0);
      expect(old.hasAcceptedCurrentTerms, isFalse);

      final accepted = ProfileModel.fromJson(
        ProfileModel.fromEntity(testProfile).toJson(),
      );
      expect(accepted.hasAcceptedCurrentTerms, isTrue);
    });

    test('AcceptTermsUseCase saves the current version and keeps the rest '
        'of the profile', () async {
      final profiles = FakeProfileRepository(
        saved: const Profile(
          gender: Gender.female,
          lookingFor: {Gender.male},
          isAdultConfirmed: true,
          acceptedSensitiveConsentVersion:
              Profile.currentSensitiveConsentVersion,
          languages: ['it'],
        ),
      );

      final result = await AcceptTermsUseCase(
        getProfileUseCase: GetProfileUseCase(profiles),
        saveProfileUseCase: SaveProfileUseCase(profiles),
      )(const NoParams());

      expect(result.isRight(), isTrue);
      expect(profiles.saved?.acceptedTermsVersion, Profile.currentTermsVersion);
      expect(profiles.saved?.languages, ['it']);
      expect(profiles.saved?.lookingFor, {Gender.male});
    });

    test(
      'AcceptTermsUseCase without a profile: ProfileMissingFailure',
      () async {
        final profiles = FakeProfileRepository();

        final result = await AcceptTermsUseCase(
          getProfileUseCase: GetProfileUseCase(profiles),
          saveProfileUseCase: SaveProfileUseCase(profiles),
        )(const NoParams());

        expect(result.getLeft().toNullable(), isA<ProfileMissingFailure>());
      },
    );
  });
}
