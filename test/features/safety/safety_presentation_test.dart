import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:provider/provider.dart';

import 'package:threemojo_app/core/config/safety_contact.dart';
import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/encounters/presentation/encounter_notice.dart';
import 'package:threemojo_app/features/encounters/presentation/providers/pro_encounters.dart';
import 'package:threemojo_app/features/nearby/domain/entities/background_location_notice.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/get_location_disclosure_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/open_app_settings_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/request_location_permission_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/open_location_settings_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/usecases/watch_nearby_people_usecase.dart';
import 'package:threemojo_app/features/nearby/domain/repositories/location_repository.dart';
import 'package:threemojo_app/features/nearby/presentation/providers/pro_nearby.dart';
import 'package:threemojo_app/features/safety/data/models/safety_rejection_model.dart';
import 'package:threemojo_app/features/safety/domain/entities/report_reason.dart';
import 'package:threemojo_app/features/safety/domain/entities/safety_rejection.dart';
import 'package:threemojo_app/features/safety/domain/usecases/block_person_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/report_person_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/watch_blocked_people_usecase.dart';
import 'package:threemojo_app/features/safety/domain/usecases/watch_safety_rejections_usecase.dart';
import 'package:threemojo_app/features/safety/presentation/pages/ui_safety.dart';
import 'package:threemojo_app/features/safety/presentation/providers/pro_safety.dart';
import 'package:threemojo_app/features/safety/presentation/widgets/cmp_person_safety_menu_button.dart';
import 'package:threemojo_app/features/safety/presentation/widgets/cmp_safety_notice_listener.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

import '../../support/build_providers.dart';
import '../../support/fake_repositories.dart';
import '../../support/fake_safety.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Ogni chiamata apre un nuovo stream di liste "Vicinanze" pilotabile.
class _FakeWatchNearbyPeopleUseCase implements WatchNearbyPeopleUseCase {
  final controllers = <StreamController<Either<Failure, List<NearbyPerson>>>>[];

  StreamController<Either<Failure, List<NearbyPerson>>> get last =>
      controllers.last;

  @override
  Stream<Either<Failure, List<NearbyPerson>>> call({
    BackgroundLocationNotice? backgroundNotice,
  }) {
    final controller = StreamController<Either<Failure, List<NearbyPerson>>>();
    controllers.add(controller);
    return controller.stream;
  }
}

class _UnusedLocationRepository implements LocationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not needed for this test');
}

NearbyPerson _person(String id) =>
    NearbyPerson(id: id, meetingChance: MeetingChance.high);

ProSafety _buildProSafety(
  FakeSessionRepository sessions,
  ({FakeSafetyRemoteDataSource remote, dynamic local, dynamic repository})
  safety,
) {
  final repository = safety.repository;
  return ProSafety(
    watchSessionUseCase: WatchSessionUseCase(sessions),
    blockPersonUseCase: BlockPersonUseCase(repository),
    reportPersonUseCase: ReportPersonUseCase(
      repository,
      BlockPersonUseCase(repository),
    ),
    watchSafetyRejectionsUseCase: WatchSafetyRejectionsUseCase(
      getCurrentSessionUseCase: GetCurrentSessionUseCase(sessions),
      repository: repository,
    ),
  );
}

void main() {
  late FakeSessionRepository sessions;

  setUp(() => sessions = FakeSessionRepository(current: testSession('s1')));

  group('ProNearby', () {
    test('hides a blocked person at once, and keeps hiding them if the '
        'server still sends them', () async {
      final safety = buildSafety();
      final watch = _FakeWatchNearbyPeopleUseCase();
      final proNearby =
          ProNearby(
            watchSessionUseCase: WatchSessionUseCase(sessions),
            watchNearbyPeopleUseCase: watch,
            openLocationSettingsUseCase: OpenLocationSettingsUseCase(
              _UnusedLocationRepository(),
            ),
            openAppSettingsUseCase: OpenAppSettingsUseCase(
              _UnusedLocationRepository(),
            ),
            getLocationDisclosureUseCase: GetLocationDisclosureUseCase(
              _UnusedLocationRepository(),
            ),
            requestLocationPermissionUseCase: RequestLocationPermissionUseCase(
              _UnusedLocationRepository(),
            ),
            watchBlockedPeopleUseCase: WatchBlockedPeopleUseCase(
              safety.repository,
            ),
          )..setBackgroundLocationNotice(
            const BackgroundLocationNotice(
              title: 't',
              body: 'b',
              channelName: 'c',
            ),
          );
      addTearDown(proNearby.dispose);
      await _settle();

      watch.last.add(Right([_person('a'), _person('b')]));
      await _settle();
      expect(proNearby.people.map((p) => p.id), ['a', 'b']);

      BlockPersonUseCase(safety.repository)('a');
      await _settle();
      expect(proNearby.people.map((p) => p.id), ['b']);

      watch.last.add(Right([_person('a'), _person('b'), _person('c')]));
      await _settle();
      expect(proNearby.people.map((p) => p.id), ['b', 'c']);
    });
  });

  group('ProEncounters', () {
    late FakeEncounterRepository encounters;
    late FakeChatRepository chat;
    late ProEncounters proEncounters;
    late List<EncounterNotice> notices;
    late FakeSafety safety;

    setUp(() async {
      encounters = FakeEncounterRepository();
      chat = FakeChatRepository();
      safety = buildSafety();
      proEncounters = buildProEncounters(
        sessions: sessions,
        encounters: encounters,
        chat: chat,
        watchBlockedPeopleUseCase: WatchBlockedPeopleUseCase(safety.repository),
      );
      notices = [];
      proEncounters.notices.listen(notices.add);
      await _settle();
    });

    tearDown(() => proEncounters.dispose());

    test('blocking the match partner closes the match here, deletes the '
        'chat and does not say "the other person left"', () async {
      encounters.push((
        incoming: [
          testRequest(
            'in1',
            EncounterRequestStatus.pending,
            otherPersonId: 'p2',
          ),
        ],
        outgoing: [
          testRequest(
            'out1',
            EncounterRequestStatus.accepted,
            otherPersonId: 'p1',
          ),
        ],
      ));
      await _settle();
      expect(proEncounters.activeMatch?.id, 'out1');

      BlockPersonUseCase(safety.repository)('p1');
      await _settle();

      expect(proEncounters.activeMatch, isNull);
      expect(proEncounters.outgoingRequests, isEmpty);
      expect(proEncounters.incomingRequests.single.otherPersonId, 'p2');
      expect(chat.deleted, ['p1']);

      // Poi il server chiude il match anche lì e lo dimentica.
      encounters.push((
        incoming: [
          testRequest(
            'in1',
            EncounterRequestStatus.pending,
            otherPersonId: 'p2',
          ),
        ],
        outgoing: [
          testRequest(
            'out1',
            EncounterRequestStatus.ended,
            otherPersonId: 'p1',
          ),
        ],
      ));
      await _settle();
      encounters.push((
        incoming: [
          testRequest(
            'in1',
            EncounterRequestStatus.pending,
            otherPersonId: 'p2',
          ),
        ],
        outgoing: const [],
      ));
      await _settle();

      expect(notices.whereType<MatchEndedByPartnerNotice>(), isEmpty);
      expect(proEncounters.activeMatch, isNull);
    });

    test(
      'a request from a blocked person disappears, badge included',
      () async {
        encounters.push((
          incoming: [
            testRequest(
              'in1',
              EncounterRequestStatus.pending,
              otherPersonId: 'p2',
            ),
          ],
          outgoing: const [],
        ));
        await _settle();
        expect(proEncounters.pendingIncomingCount, 1);

        ReportPersonUseCase(
          safety.repository,
          BlockPersonUseCase(safety.repository),
        )(const ReportPersonParams(personId: 'p2', reason: ReportReason.spam));
        await _settle();

        expect(proEncounters.incomingRequests, isEmpty);
        expect(proEncounters.pendingIncomingCount, 0);
      },
    );
  });

  test(
    'ProSafety forwards the rejections of the server for this session',
    () async {
      final safety = buildSafety();
      final proSafety = _buildProSafety(sessions, safety);
      addTearDown(proSafety.dispose);
      final rejections = <SafetyRejection>[];
      proSafety.rejections.listen(rejections.add);
      await _settle();

      expect(proSafety.block('p1').isRight(), isTrue);
      safety.remote.rejections.add(
        const SafetyRejectionModel(
          action: SafetyAction.block,
          reason: SafetyRejectionReason.unknownPerson,
          personId: 'p1',
        ),
      );
      await _settle();

      expect(rejections.single.reason, SafetyRejectionReason.unknownPerson);
    },
  );

  group('widgets', () {
    late AppLocalizations l10n;
    late FakeSafety safety;
    late ProSafety proSafety;

    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
      safety = buildSafety();
      proSafety = _buildProSafety(sessions, safety);
    });

    tearDown(() => proSafety.dispose());

    Future<void> pumpMenu(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: proSafety,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CmpSafetyNoticeListener(
              child: Scaffold(
                body: Center(child: CmpPersonSafetyMenuButton(personId: 'p1')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openMenu(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip(l10n.safety_menu_tooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('the ⋯ button is labelled for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpMenu(tester);

      expect(
        tester.getSemantics(find.byType(IconButton)),
        isSemantics(
          tooltip: l10n.safety_menu_tooltip,
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('Block asks for confirmation, says honestly how long it '
        'lasts, and only then blocks', (tester) async {
      await pumpMenu(tester);

      await openMenu(tester, l10n.block);
      expect(find.text(l10n.block_dialog_body), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(safety.remote.blocked, isEmpty);

      await openMenu(tester, l10n.block);
      await tester.tap(find.widgetWithText(FilledButton, l10n.block));
      await tester.pumpAndSettle();

      expect(safety.remote.blocked, ['p1']);
      expect(find.text(l10n.person_blocked), findsOneWidget);
    });

    testWidgets('offline the block is not sent, and the snackbar says so', (
      tester,
    ) async {
      safety.remote.offline = true;
      await pumpMenu(tester);

      await openMenu(tester, l10n.block);
      await tester.tap(find.widgetWithText(FilledButton, l10n.block));
      await tester.pumpAndSettle();

      expect(find.text(l10n.action_not_sent_offline), findsOneWidget);
    });

    testWidgets('Report needs a reason from the closed list, says it also '
        'blocks, and sends only the reason code', (tester) async {
      await pumpMenu(tester);

      await openMenu(tester, l10n.report);
      expect(find.text(l10n.report_dialog_body), findsOneWidget);
      final send = find.widgetWithText(FilledButton, l10n.report_send);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);

      await tester.tap(find.text(l10n.report_reason_underage));
      await tester.pump();
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(safety.remote.reported, [('p1', ReportReason.underage)]);
      expect(find.text(l10n.person_reported), findsOneWidget);
    });

    testWidgets('a rejection from the server becomes a translated snackbar', (
      tester,
    ) async {
      await pumpMenu(tester);
      // `ProSafety` è nato fuori dal test (nel `setUp`): i suoi stream
      // girano col tempo vero, non con quello finto di `testWidgets`.
      await tester.runAsync(() async {
        await _settle();
        safety.remote.rejections.add(
          const SafetyRejectionModel(
            action: SafetyAction.report,
            reason: SafetyRejectionReason.unknownPerson,
          ),
        );
        await _settle();
      });
      await tester.pumpAndSettle();

      expect(find.text(l10n.report_rejected_person_gone), findsOneWidget);
    });

    testWidgets('the safety page shows the published contact and copies it', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const UiSafety(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.byTooltip(l10n.copy_email), 200);
      expect(find.text(SafetyContact.email), findsOneWidget);
      await tester.tap(find.byTooltip(l10n.copy_email));
      await tester.pumpAndSettle();

      expect(copied, SafetyContact.email);
      expect(find.text(l10n.email_copied), findsOneWidget);
    });
  });
}
