import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/demo/demo_mode.dart';
import 'core/unlock/unlock_token_store.dart';
import 'core/utils/illustrated_avatar.dart';
import 'features/chat/data/datasources/chat_remote_data_source.dart';
import 'features/chat/data/datasources/chat_remote_data_source_fake_impl.dart';
import 'features/chat/data/repositories/chat_repository_impl.dart';
import 'features/chat/domain/repositories/chat_repository.dart';
import 'features/chat/domain/usecases/clear_chat_session_usecase.dart';
import 'features/chat/domain/usecases/delete_conversation_usecase.dart';
import 'features/chat/domain/usecases/get_messages_usecase.dart';
import 'features/chat/domain/usecases/get_or_create_conversation_usecase.dart';
import 'features/chat/domain/usecases/send_message_usecase.dart';
import 'features/chat/domain/usecases/start_receiving_chat_messages_usecase.dart';
import 'features/chat/domain/usecases/watch_incoming_chat_messages_usecase.dart';
import 'features/chat/domain/usecases/watch_undelivered_chat_messages_usecase.dart';
import 'features/chat/presentation/providers/pro_chat.dart';
import 'features/demo/domain/usecases/start_demo_session_usecase.dart';
import 'features/demo/presentation/providers/pro_demo.dart';
import 'features/demo/presentation/providers/pro_demo_tour.dart';
import 'features/demo/presentation/widgets/cmp_demo_banner.dart';
import 'features/encounters/data/datasources/encounter_remote_data_source.dart';
import 'features/encounters/data/datasources/encounter_remote_data_source_fake_impl.dart';
import 'features/encounters/data/repositories/encounter_repository_impl.dart';
import 'features/encounters/domain/entities/encounter_proposal.dart';
import 'features/encounters/domain/repositories/encounter_repository.dart';
import 'features/encounters/domain/usecases/clear_encounter_session_state_usecase.dart';
import 'features/encounters/domain/usecases/detect_ended_match_usecase.dart';
import 'features/encounters/domain/usecases/end_match_usecase.dart';
import 'features/encounters/domain/usecases/forget_ended_match_usecase.dart';
import 'features/encounters/domain/usecases/respond_to_encounter_request_usecase.dart';
import 'features/encounters/domain/usecases/send_encounter_request_usecase.dart';
import 'features/encounters/domain/usecases/watch_encounter_rejections_usecase.dart';
import 'features/encounters/domain/usecases/watch_encounter_requests_usecase.dart';
import 'features/encounters/presentation/providers/pro_encounters.dart';
import 'features/nearby/data/datasources/location_local_data_source.dart';
import 'features/nearby/data/datasources/location_local_data_source_fake_impl.dart';
import 'features/nearby/data/datasources/nearby_remote_data_source.dart';
import 'features/nearby/data/datasources/nearby_remote_data_source_fake_impl.dart';
import 'features/nearby/data/repositories/location_repository_impl.dart';
import 'features/nearby/data/repositories/nearby_repository_impl.dart';
import 'features/nearby/domain/entities/background_location_notice.dart';
import 'features/nearby/domain/repositories/location_repository.dart';
import 'features/nearby/domain/repositories/nearby_repository.dart';
import 'features/nearby/domain/usecases/get_current_location_usecase.dart';
import 'features/nearby/domain/usecases/get_location_disclosure_usecase.dart';
import 'features/nearby/domain/usecases/open_app_settings_usecase.dart';
import 'features/nearby/domain/usecases/open_location_settings_usecase.dart';
import 'features/nearby/domain/usecases/request_location_permission_usecase.dart';
import 'features/nearby/domain/usecases/stop_being_visible_usecase.dart';
import 'features/nearby/domain/usecases/watch_nearby_people_usecase.dart';
import 'features/nearby/domain/usecases/watch_position_usecase.dart';
import 'features/nearby/presentation/providers/pro_nearby.dart';
import 'features/paywall/data/datasources/paywall_local_data_source.dart';
import 'features/paywall/data/datasources/paywall_local_data_source_impl.dart';
import 'features/paywall/data/datasources/paywall_remote_data_source.dart';
import 'features/paywall/data/datasources/paywall_remote_data_source_fake_impl.dart';
import 'features/paywall/data/datasources/store_billing_data_source.dart';
import 'features/paywall/data/datasources/store_billing_data_source_fake_impl.dart';
import 'features/paywall/data/repositories/paywall_repository_impl.dart';
import 'features/paywall/data/repositories/store_repository_impl.dart';
import 'features/paywall/domain/repositories/paywall_repository.dart';
import 'features/paywall/domain/repositories/store_repository.dart';
import 'features/paywall/domain/usecases/get_unlock_offer_usecase.dart';
import 'features/paywall/domain/usecases/get_unlock_status_usecase.dart';
import 'features/paywall/domain/usecases/purchase_unlock_usecase.dart';
import 'features/paywall/domain/usecases/redeem_store_purchase_usecase.dart';
import 'features/paywall/domain/usecases/retry_unfinished_purchases_usecase.dart';
import 'features/paywall/domain/usecases/watch_unfinished_purchases_usecase.dart';
import 'features/paywall/presentation/providers/pro_paywall.dart';
import 'features/profile/data/datasources/profile_local_data_source.dart';
import 'features/profile/data/datasources/profile_local_data_source_fake_impl.dart';
import 'features/profile/data/models/profile_model.dart';
import 'features/profile/data/repositories/profile_repository_impl.dart';
import 'features/profile/domain/entities/profile.dart';
import 'features/profile/domain/repositories/profile_repository.dart';
import 'features/profile/domain/usecases/get_profile_usecase.dart';
import 'features/safety/data/datasources/blocked_people_local_data_source.dart';
import 'features/safety/data/datasources/blocked_people_local_data_source_impl.dart';
import 'features/safety/data/datasources/safety_remote_data_source.dart';
import 'features/safety/data/datasources/safety_remote_data_source_fake_impl.dart';
import 'features/safety/data/repositories/safety_repository_impl.dart';
import 'features/safety/domain/repositories/safety_repository.dart';
import 'features/safety/domain/usecases/block_person_usecase.dart';
import 'features/safety/domain/usecases/clear_safety_session_state_usecase.dart';
import 'features/safety/domain/usecases/report_person_usecase.dart';
import 'features/safety/domain/usecases/watch_blocked_people_usecase.dart';
import 'features/safety/domain/usecases/watch_safety_rejections_usecase.dart';
import 'features/safety/presentation/providers/pro_safety.dart';
import 'features/session/data/datasources/connection_remote_data_source.dart';
import 'features/session/data/datasources/connection_remote_data_source_fake_impl.dart';
import 'features/session/data/datasources/face_detection_local_data_source.dart';
import 'features/session/data/datasources/face_detection_local_data_source_fake_impl.dart';
import 'features/session/data/datasources/selfie_local_data_source.dart';
import 'features/session/data/datasources/selfie_local_data_source_fake_impl.dart';
import 'features/session/data/datasources/session_local_data_source.dart';
import 'features/session/data/datasources/session_local_data_source_impl.dart';
import 'features/session/data/repositories/connection_repository_impl.dart';
import 'features/session/data/repositories/face_detection_repository_impl.dart';
import 'features/session/data/repositories/selfie_repository_impl.dart';
import 'features/session/data/repositories/session_repository_impl.dart';
import 'features/session/domain/repositories/connection_repository.dart';
import 'features/session/domain/repositories/face_detection_repository.dart';
import 'features/session/domain/repositories/selfie_repository.dart';
import 'features/session/domain/repositories/session_repository.dart';
import 'features/session/domain/usecases/check_connection_usecase.dart';
import 'features/session/domain/usecases/check_selfie_has_face_usecase.dart';
import 'features/session/domain/usecases/discard_selfie_files_usecase.dart';
import 'features/session/domain/usecases/end_session_usecase.dart';
import 'features/session/domain/usecases/flip_selfie_usecase.dart';
import 'features/session/domain/usecases/get_current_session_usecase.dart';
import 'features/session/domain/usecases/start_session_usecase.dart';
import 'features/session/domain/usecases/take_selfie_usecase.dart';
import 'features/session/domain/usecases/watch_connection_status_usecase.dart';
import 'features/session/domain/usecases/watch_server_session_restarts_usecase.dart';
import 'features/session/domain/usecases/watch_session_usecase.dart';
import 'features/session/presentation/providers/pro_connection.dart';
import 'features/session/presentation/providers/pro_session.dart';
import 'l10n/generated/app_localizations.dart';

/// Il "mondo" della **demo dichiarata**: la seconda radice di composizione
/// dell'app, accanto ad `App`. Esiste solo mentre `ProDemo.isActive`: allora
/// `RaenApp` lo mette sopra il `Navigator`, così **tutte** le pagine (anche
/// tendine, dialoghi e la pagina del match) leggono i provider della demo,
/// che coprono quelli reali con gli stessi tipi.
///
/// Perché così (e non una pagina a parte con un suo `Navigator`): `UiHome`,
/// `CmpMatchGate`, gli avvisi e tutte le pagine dell'app restano **gli
/// stessi**, senza un ramo "se demo" in ogni feature; i dialoghi (aperti sul
/// `Navigator` principale) vedono comunque la demo; il tasto indietro di
/// Android non può farne uscire saltando la pulizia.
///
/// Dentro:
/// - **solo datasource finti o in memoria**, gli stessi `*FakeImpl` della
///   modalità finta di sviluppo (qui anche in release), più quelli della
///   demo (GPS, collegamento, selfie, volto): nessun messaggio al server,
///   nessun WebSocket (`RealtimeConnection` non viene mai toccato), nessuna
///   posizione, nessun permesso, nessuna fotocamera, nessun negozio vero
///   (`StoreBillingDataSourceFakeImpl.demo`, sblocco gratuito in un
///   `UnlockTokenStore.inMemory`), nessuna scrittura sul telefono;
/// - una sessione **tutta sua** (`SessionLocalDataSourceImpl` nuovo, in
///   memoria), avviata da `ProDemoTour` con `StartDemoSessionUseCase`
///   (selfie illustrato, profilo neutro): la sessione reale resta `null`;
/// - foto delle persone: avatar **illustrati** generati sul telefono
///   (`illustratedAvatarPng`), mai foto di persone reali;
/// - [DemoMode] sopra tutto, perché ogni persona mostri il badge "Demo", e
///   il banner fisso `CmpDemoBanner`.
///
/// Uscita (banner o End): `EndSessionUseCase` della demo — gli stessi passi
/// di pulizia di End, sui datasource della demo —, poi si chiudono le pagine
/// aperte e `ProDemo.leave`: questo widget sparisce con tutto ciò che ha
/// creato. Del mondo reale la demo legge solo `ProDemo` (per uscire): anche
/// il profilo è il suo (in memoria, quello neutro di
/// `StartDemoSessionUseCase`), e nella demo lo Start non è raggiungibile
/// (`UiHome` non mostra la home offline dentro la demo).
class DemoScope extends StatelessWidget {
  const DemoScope({super.key, required this.navigatorKey, required this.child});

  /// Il `Navigator` dell'app (questo widget sta sopra di lui): per chiudere
  /// le pagine della demo all'uscita.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// Prefisso degli pseudonimi delle persone dimostrative (`demo-1` …
  /// `demo-5`): lo stesso in "Vicinanze" e nelle richieste in arrivo.
  static const String personIdPrefix = 'demo';

  /// Dopo quanto (e poi ogni quanto) arriva una richiesta in entrata.
  static const Duration incomingRequestInterval = Duration(seconds: 15);

  /// Dopo quanto arriva il "sì" a una tua richiesta.
  static const Duration responseDelay = Duration(seconds: 3);

  static String _personId(int index) =>
      NearbyRemoteDataSourceFakeImpl.personId(personIdPrefix, index);

  /// La foto illustrata della persona dimostrativa [personId] (`demo-<n>`).
  static Uint8List? _avatarOf(String personId) {
    final index = int.tryParse(personId.split('-').last);
    if (index == null) return null;
    return illustratedAvatarPng(
      NearbyRemoteDataSourceFakeImpl.avatarSeedOf(index),
    );
  }

  /// Chi ti scrive, nell'ordine (il primo con cui non c'è già una
  /// richiesta): la persona 4 (libera dal paywall) e poi la 1 (la più
  /// vicina, bloccata finché non sblocchi). Ciò che mostrano del profilo è
  /// quello che hanno in "Vicinanze" (`NearbyRemoteDataSourceFakeImpl`).
  static List<FakeIncomingRequester> _incomingRequesters() => [
    FakeIncomingRequester(
      personId: _personId(4),
      proposal: EncounterProposal.sayHi,
      selfieBytes: _avatarOf(_personId(4)),
      visibleGender: Gender.nonBinary,
    ),
    FakeIncomingRequester(
      personId: _personId(1),
      proposal: EncounterProposal.drink,
      selfieBytes: _avatarOf(_personId(1)),
      intent: MeetIntent.chat,
      languages: const ['it', 'en'],
      visibleGender: Gender.female,
    ),
  ];

  /// Lo stesso End della sessione reale (`App`), coi passi di pulizia delle
  /// stesse feature, ma letti da qui: i repository della demo.
  static EndSessionUseCase _endSessionUseCase(BuildContext context) =>
      EndSessionUseCase(
        repository: context.read(),
        teardownSteps: [
          StopBeingVisibleUseCase(context.read()),
          ClearEncounterSessionStateUseCase(context.read()),
          ClearChatSessionUseCase(context.read()),
          ClearSafetySessionStateUseCase(context.read()),
          DiscardSelfieFilesUseCase(context.read()),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return MultiProvider(
      providers: [
        // --- data: solo finti o in memoria ---
        Provider<SessionLocalDataSource>(
          create: (_) => SessionLocalDataSourceImpl(),
        ),
        Provider<SessionRepository>(
          create: (context) => SessionRepositoryImpl(context.read()),
        ),
        Provider<ConnectionRemoteDataSource>(
          create: (_) => ConnectionRemoteDataSourceFakeImpl(),
        ),
        Provider<ConnectionRepository>(
          create: (context) => ConnectionRepositoryImpl(context.read()),
        ),
        Provider<SelfieLocalDataSource>(
          create: (_) => SelfieLocalDataSourceFakeImpl(),
        ),
        Provider<SelfieRepository>(
          create: (context) => SelfieRepositoryImpl(context.read()),
        ),
        Provider<FaceDetectionLocalDataSource>(
          create: (_) => FaceDetectionLocalDataSourceFakeImpl(),
        ),
        Provider<FaceDetectionRepository>(
          create: (context) => FaceDetectionRepositoryImpl(context.read()),
        ),
        // Il profilo vero (cifrato sul telefono) la demo non lo legge mai.
        Provider<ProfileLocalDataSource>(
          create: (_) => ProfileLocalDataSourceFakeImpl(
            initial: ProfileModel.fromEntity(
              StartDemoSessionUseCase.demoProfile,
            ),
          ),
        ),
        Provider<ProfileRepository>(
          create: (context) => ProfileRepositoryImpl(context.read()),
        ),
        Provider<LocationLocalDataSource>(
          create: (_) => LocationLocalDataSourceFakeImpl(),
        ),
        Provider<LocationRepository>(
          create: (context) => LocationRepositoryImpl(context.read()),
        ),
        // Lo sblocco della demo: solo in memoria, condiviso tra il paywall
        // e la "Vicinanze" della demo — mai quello vero.
        Provider<UnlockTokenStore>(create: (_) => UnlockTokenStore.inMemory()),
        Provider<NearbyRemoteDataSource>(
          create: (context) => NearbyRemoteDataSourceFakeImpl(
            unlockTokenStore: context.read(),
            viewerMustStayPut: false,
            peopleComeAndGo: false,
            idPrefix: personIdPrefix,
          ),
          dispose: (_, dataSource) => dataSource.disconnect(),
        ),
        Provider<NearbyRepository>(
          create: (context) => NearbyRepositoryImpl(context.read()),
        ),
        Provider<PaywallLocalDataSource>(
          create: (context) => PaywallLocalDataSourceImpl(
            store: context.read<UnlockTokenStore>(),
          ),
        ),
        Provider<PaywallRemoteDataSource>(
          create: (_) => PaywallRemoteDataSourceFakeImpl(),
        ),
        Provider<PaywallRepository>(
          create: (context) =>
              PaywallRepositoryImpl(context.read(), context.read()),
        ),
        Provider<StoreBillingDataSource>(
          create: (_) => StoreBillingDataSourceFakeImpl.demo(),
        ),
        Provider<StoreRepository>(
          create: (context) => StoreRepositoryImpl(context.read()),
        ),
        Provider<RedeemStorePurchaseUseCase>(
          create: (context) => RedeemStorePurchaseUseCase(
            paywallRepository: context.read(),
            storeRepository: context.read(),
          ),
        ),
        Provider<EncounterRemoteDataSource>(
          create: (_) => EncounterRemoteDataSourceFakeImpl(
            incomingTickInterval: incomingRequestInterval,
            responseDelay: responseDelay,
            newIncomingProbability: 1,
            acceptProbability: 1,
            incomingRequesters: _incomingRequesters(),
            selfieOf: _avatarOf,
          ),
          dispose: (_, dataSource) => dataSource.reset(),
        ),
        Provider<EncounterRepository>(
          create: (context) => EncounterRepositoryImpl(context.read()),
        ),
        Provider<ChatRemoteDataSource>(
          create: (_) => ChatRemoteDataSourceFakeImpl(
            replies: [
              l10n.demo_chat_reply_1,
              l10n.demo_chat_reply_2,
              l10n.demo_chat_reply_3,
            ],
            purgeLegacyStorage: false,
          ),
          dispose: (_, dataSource) => dataSource.reset(),
        ),
        Provider<ChatRepository>(
          create: (context) => ChatRepositoryImpl(context.read()),
        ),
        Provider<SafetyRemoteDataSource>(
          create: (_) => SafetyRemoteDataSourceFakeImpl(),
        ),
        Provider<BlockedPeopleLocalDataSource>(
          create: (_) => BlockedPeopleLocalDataSourceImpl(),
        ),
        Provider<SafetyRepository>(
          create: (context) =>
              SafetyRepositoryImpl(context.read(), context.read()),
        ),
        // --- presentation: gli stessi provider dell'app, sul mondo della
        // demo ---
        ChangeNotifierProvider<ProSession>(
          create: (context) => ProSession(
            watchSessionUseCase: WatchSessionUseCase(context.read()),
            startSessionUseCase: StartSessionUseCase(
              repository: context.read(),
              checkSelfieHasFaceUseCase: CheckSelfieHasFaceUseCase(
                context.read(),
              ),
              getProfileUseCase: GetProfileUseCase(context.read()),
            ),
            endSessionUseCase: _endSessionUseCase(context),
            checkSelfieHasFaceUseCase: CheckSelfieHasFaceUseCase(
              context.read(),
            ),
            takeSelfieUseCase: TakeSelfieUseCase(context.read()),
            flipSelfieUseCase: FlipSelfieUseCase(context.read()),
          ),
        ),
        ChangeNotifierProvider<ProConnection>(
          create: (context) => ProConnection(
            watchConnectionStatusUseCase: WatchConnectionStatusUseCase(
              context.read(),
            ),
            watchServerSessionRestartsUseCase:
                WatchServerSessionRestartsUseCase(context.read()),
            checkConnectionUseCase: CheckConnectionUseCase(context.read()),
          ),
        ),
        ChangeNotifierProvider<ProNearby>(
          create: (context) =>
              ProNearby(
                  watchSessionUseCase: WatchSessionUseCase(context.read()),
                  watchNearbyPeopleUseCase: WatchNearbyPeopleUseCase(
                    getCurrentSessionUseCase: GetCurrentSessionUseCase(
                      context.read(),
                    ),
                    getCurrentLocationUseCase: GetCurrentLocationUseCase(
                      context.read(),
                    ),
                    watchPositionUseCase: WatchPositionUseCase(context.read()),
                    nearbyRepository: context.read(),
                  ),
                  openLocationSettingsUseCase: OpenLocationSettingsUseCase(
                    context.read(),
                  ),
                  openAppSettingsUseCase: OpenAppSettingsUseCase(
                    context.read(),
                  ),
                  getLocationDisclosureUseCase: GetLocationDisclosureUseCase(
                    context.read(),
                  ),
                  requestLocationPermissionUseCase:
                      RequestLocationPermissionUseCase(context.read()),
                  watchBlockedPeopleUseCase: WatchBlockedPeopleUseCase(
                    context.read(),
                  ),
                )
                // Obbligatori lungo la catena: il GPS finto li ignora.
                ..setBackgroundLocationNotice(
                  BackgroundLocationNotice(
                    title: l10n.background_location_notification_title,
                    body: l10n.background_location_notification_body,
                    channelName: l10n.background_location_notification_channel,
                  ),
                ),
        ),
        ChangeNotifierProvider<ProPaywall>(
          create: (context) => ProPaywall(
            watchSessionUseCase: WatchSessionUseCase(context.read()),
            getUnlockStatusUseCase: GetUnlockStatusUseCase(context.read()),
            purchaseUnlockUseCase: PurchaseUnlockUseCase(
              storeRepository: context.read(),
              redeemStorePurchaseUseCase: context.read(),
            ),
            getUnlockOfferUseCase: GetUnlockOfferUseCase(context.read()),
            watchUnfinishedPurchasesUseCase: WatchUnfinishedPurchasesUseCase(
              storeRepository: context.read(),
              redeemStorePurchaseUseCase: context.read(),
            ),
            retryUnfinishedPurchasesUseCase: RetryUnfinishedPurchasesUseCase(
              storeRepository: context.read(),
              redeemStorePurchaseUseCase: context.read(),
            ),
          ),
        ),
        ChangeNotifierProvider<ProEncounters>(
          create: (context) => ProEncounters(
            watchSessionUseCase: WatchSessionUseCase(context.read()),
            watchServerSessionRestartsUseCase:
                WatchServerSessionRestartsUseCase(context.read()),
            watchEncounterRequestsUseCase: WatchEncounterRequestsUseCase(
              getCurrentSessionUseCase: GetCurrentSessionUseCase(
                context.read(),
              ),
              repository: context.read(),
            ),
            watchEncounterRejectionsUseCase: WatchEncounterRejectionsUseCase(
              getCurrentSessionUseCase: GetCurrentSessionUseCase(
                context.read(),
              ),
              repository: context.read(),
            ),
            sendEncounterRequestUseCase: SendEncounterRequestUseCase(
              context.read(),
            ),
            respondToEncounterRequestUseCase: RespondToEncounterRequestUseCase(
              context.read(),
            ),
            endMatchUseCase: EndMatchUseCase(
              context.read(),
              DeleteConversationUseCase(context.read()),
            ),
            detectEndedMatchUseCase: DetectEndedMatchUseCase(
              ForgetEndedMatchUseCase(
                DeleteConversationUseCase(context.read()),
              ),
            ),
            watchBlockedPeopleUseCase: WatchBlockedPeopleUseCase(
              context.read(),
            ),
          ),
        ),
        ChangeNotifierProvider<ProSafety>(
          create: (context) => ProSafety(
            watchSessionUseCase: WatchSessionUseCase(context.read()),
            blockPersonUseCase: BlockPersonUseCase(context.read()),
            reportPersonUseCase: ReportPersonUseCase(
              context.read(),
              BlockPersonUseCase(context.read()),
            ),
            watchSafetyRejectionsUseCase: WatchSafetyRejectionsUseCase(
              getCurrentSessionUseCase: GetCurrentSessionUseCase(
                context.read(),
              ),
              repository: context.read(),
            ),
          ),
        ),
        ChangeNotifierProvider<ProChat>(
          create: (context) => ProChat(
            watchSessionUseCase: WatchSessionUseCase(context.read()),
            getOrCreateConversationUseCase: GetOrCreateConversationUseCase(
              context.read(),
            ),
            getMessagesUseCase: GetMessagesUseCase(context.read()),
            sendMessageUseCase: SendMessageUseCase(context.read()),
            startReceivingChatMessagesUseCase:
                StartReceivingChatMessagesUseCase(context.read()),
            watchIncomingChatMessagesUseCase: WatchIncomingChatMessagesUseCase(
              getCurrentSessionUseCase: GetCurrentSessionUseCase(
                context.read(),
              ),
              repository: context.read(),
            ),
            watchUndeliveredChatMessagesUseCase:
                WatchUndeliveredChatMessagesUseCase(
                  getCurrentSessionUseCase: GetCurrentSessionUseCase(
                    context.read(),
                  ),
                  repository: context.read(),
                ),
          ),
        ),
        // Creato subito: è lui ad avviare la sessione della demo.
        ChangeNotifierProvider<ProDemoTour>(
          lazy: false,
          create: (context) => ProDemoTour(
            startDemoSessionUseCase: StartDemoSessionUseCase(
              repository: context.read(),
              takeSelfieUseCase: TakeSelfieUseCase(context.read()),
            ),
            endSessionUseCase: _endSessionUseCase(context),
            watchSessionUseCase: WatchSessionUseCase(context.read()),
          ),
        ),
      ],
      child: DemoMode(
        child: _DemoExitWatcher(
          navigatorKey: navigatorKey,
          child: Column(
            children: [
              const _Banner(),
              Expanded(
                // Il banner occupa già la barra di stato: le pagine sotto
                // non devono lasciarle spazio una seconda volta.
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    final tour = context.watch<ProDemoTour>();
    return CmpDemoBanner(isExiting: tour.isExiting, onExit: tour.exit);
  }
}

/// Quando la sessione della demo è finita (`ProDemoTour.isFinished`):
/// chiude le pagine aperte nella demo (richieste, match, dialoghi) e poi la
/// demo stessa (`ProDemo.leave`, nel mondo reale) — si torna alla home
/// offline vera.
class _DemoExitWatcher extends StatefulWidget {
  const _DemoExitWatcher({required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<_DemoExitWatcher> createState() => _DemoExitWatcherState();
}

class _DemoExitWatcherState extends State<_DemoExitWatcher> {
  bool _leaving = false;

  @override
  Widget build(BuildContext context) {
    final isFinished = context.select<ProDemoTour, bool>(
      (tour) => tour.isFinished,
    );
    if (isFinished && !_leaving) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _leave());
    }
    return widget.child;
  }

  void _leave() {
    if (!mounted) return;
    widget.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    // Nessun avviso della demo ("Accettata", "Bloccata"…) deve restare a
    // schermo sopra la home vera.
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    context.read<ProDemo>().leave();
  }
}
