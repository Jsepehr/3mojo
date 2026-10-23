import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/store_config.dart';
import 'core/theme/app_theme.dart';
import 'features/chat/data/datasources/chat_remote_data_source.dart';
import 'features/chat/data/datasources/chat_remote_data_source_fake_impl.dart';
import 'features/chat/data/datasources/chat_remote_data_source_impl.dart';
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
import 'features/encounters/data/datasources/encounter_remote_data_source.dart';
import 'features/encounters/data/datasources/encounter_remote_data_source_fake_impl.dart';
import 'features/encounters/data/datasources/encounter_remote_data_source_impl.dart';
import 'features/encounters/data/repositories/encounter_repository_impl.dart';
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
import 'features/encounters/presentation/widgets/cmp_encounter_notice_listener.dart';
import 'features/encounters/presentation/widgets/cmp_match_gate.dart';
import 'features/nearby/data/datasources/location_local_data_source.dart';
import 'features/nearby/data/datasources/location_local_data_source_impl.dart';
import 'features/nearby/data/datasources/nearby_remote_data_source.dart';
import 'features/nearby/data/datasources/nearby_remote_data_source_fake_impl.dart';
import 'features/nearby/data/datasources/nearby_remote_data_source_impl.dart';
import 'features/nearby/data/repositories/location_repository_impl.dart';
import 'features/nearby/data/repositories/nearby_repository_impl.dart';
import 'features/nearby/domain/repositories/location_repository.dart';
import 'features/nearby/domain/repositories/nearby_repository.dart';
import 'features/nearby/domain/usecases/get_current_location_usecase.dart';
import 'features/nearby/domain/usecases/open_app_settings_usecase.dart';
import 'features/nearby/domain/usecases/open_location_settings_usecase.dart';
import 'features/nearby/domain/usecases/stop_being_visible_usecase.dart';
import 'features/nearby/domain/usecases/watch_nearby_people_usecase.dart';
import 'features/nearby/domain/usecases/watch_position_usecase.dart';
import 'features/nearby/presentation/providers/pro_nearby.dart';
import 'features/paywall/data/datasources/paywall_local_data_source.dart';
import 'features/paywall/data/datasources/paywall_local_data_source_impl.dart';
import 'features/paywall/data/datasources/paywall_remote_data_source.dart';
import 'features/paywall/data/datasources/paywall_remote_data_source_fake_impl.dart';
import 'features/paywall/data/datasources/paywall_remote_data_source_impl.dart';
import 'features/paywall/data/datasources/store_billing_data_source.dart';
import 'features/paywall/data/datasources/store_billing_data_source_fake_impl.dart';
import 'features/paywall/data/datasources/store_billing_data_source_impl.dart';
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
import 'features/paywall/presentation/widgets/cmp_unlock_expired_listener.dart';
import 'features/profile/data/datasources/profile_local_data_source.dart';
import 'features/profile/data/datasources/profile_local_data_source_impl.dart';
import 'features/profile/data/repositories/profile_repository_impl.dart';
import 'features/profile/domain/repositories/profile_repository.dart';
import 'features/profile/domain/usecases/delete_profile_usecase.dart';
import 'features/profile/domain/usecases/get_profile_usecase.dart';
import 'features/profile/domain/usecases/save_profile_usecase.dart';
import 'features/profile/presentation/providers/pro_profile.dart';
import 'features/safety/data/datasources/blocked_people_local_data_source.dart';
import 'features/safety/data/datasources/blocked_people_local_data_source_impl.dart';
import 'features/safety/data/datasources/safety_remote_data_source.dart';
import 'features/safety/data/datasources/safety_remote_data_source_fake_impl.dart';
import 'features/safety/data/datasources/safety_remote_data_source_impl.dart';
import 'features/safety/data/repositories/safety_repository_impl.dart';
import 'features/safety/domain/repositories/safety_repository.dart';
import 'features/safety/domain/usecases/block_person_usecase.dart';
import 'features/safety/domain/usecases/clear_safety_session_state_usecase.dart';
import 'features/safety/domain/usecases/report_person_usecase.dart';
import 'features/safety/domain/usecases/watch_blocked_people_usecase.dart';
import 'features/safety/domain/usecases/watch_safety_rejections_usecase.dart';
import 'features/safety/presentation/providers/pro_safety.dart';
import 'features/safety/presentation/widgets/cmp_safety_notice_listener.dart';
import 'features/session/data/datasources/connection_remote_data_source.dart';
import 'features/session/data/datasources/connection_remote_data_source_impl.dart';
import 'features/session/data/datasources/face_detection_local_data_source.dart';
import 'features/session/data/datasources/face_detection_local_data_source_impl.dart';
import 'features/session/data/datasources/selfie_local_data_source.dart';
import 'features/session/data/datasources/selfie_local_data_source_impl.dart';
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
import 'features/session/domain/usecases/watch_session_closed_by_server_usecase.dart';
import 'features/session/domain/usecases/watch_session_usecase.dart';
import 'features/session/domain/usecases/withdraw_profile_usecase.dart';
import 'features/session/presentation/pages/ui_home.dart';
import 'features/session/presentation/providers/pro_connection.dart';
import 'features/session/presentation/providers/pro_session.dart';
import 'features/session/presentation/widgets/cmp_connection_notice_listener.dart';
import 'features/settings/data/datasources/settings_local_data_source.dart';
import 'features/settings/data/datasources/settings_local_data_source_impl.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/repositories/settings_repository.dart';
import 'features/settings/domain/usecases/get_fake_mode_usecase.dart';
import 'features/settings/domain/usecases/get_language_usecase.dart';
import 'features/settings/domain/usecases/get_theme_mode_usecase.dart';
import 'features/settings/domain/usecases/set_fake_mode_usecase.dart';
import 'features/settings/domain/usecases/set_language_usecase.dart';
import 'features/settings/domain/usecases/set_theme_mode_usecase.dart';
import 'features/settings/presentation/providers/pro_settings.dart';
import 'l10n/generated/app_localizations.dart';

/// Widget radice: registra tutti i provider (uno per feature, dal
/// datasource al ChangeNotifier) e apre su `UiHome`, avvolta da
/// `CmpMatchGate` così un match può prendere il controllo da qualsiasi punto.
/// `fakeMode` (letta in `main.dart` prima di costruire l'albero) sceglie i
/// datasource finti al posto di quelli reali per nearby/encounters/chat/
/// paywall/safety — le uniche feature che dipendono dal backend `server/`.
class App extends StatelessWidget {
  const App({required this.fakeMode, super.key});

  /// La modalità finta esiste solo nei build di debug: in release la voce
  /// non si vede e i datasource sono sempre quelli reali (vedi
  /// `GetFakeModeUseCase`).
  static const bool fakeModeAvailable = kDebugMode;

  final bool fakeMode;

  /// End compone i passi di pulizia delle altre feature tramite il
  /// contratto `SessionTeardownUseCase` di `session/`: la dipendenza va solo
  /// da loro verso `session/`, mai al contrario. Condiviso dal bottone End
  /// (`ProSession`) e dalla cancellazione del profilo da online
  /// (`ProProfile`).
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
    return MultiProvider(
      providers: [
        // --- data: datasource e repository (prima di tutti i provider di
        // stato, che li leggono) ---
        Provider<SessionLocalDataSource>(
          create: (_) => SessionLocalDataSourceImpl(),
        ),
        Provider<SessionRepository>(
          create: (context) => SessionRepositoryImpl(context.read()),
        ),
        // Non pigro: deve contare i benvenuti del server fin dal primo
        // collegamento (vedi `ConnectionRemoteDataSourceImpl`).
        Provider<ConnectionRemoteDataSource>(
          lazy: false,
          create: (_) => ConnectionRemoteDataSourceImpl(),
        ),
        Provider<ConnectionRepository>(
          create: (context) => ConnectionRepositoryImpl(context.read()),
        ),
        Provider<SelfieLocalDataSource>(
          create: (_) => SelfieLocalDataSourceImpl(),
        ),
        Provider<SelfieRepository>(
          create: (context) => SelfieRepositoryImpl(context.read()),
        ),
        Provider<FaceDetectionLocalDataSource>(
          create: (_) => FaceDetectionLocalDataSourceImpl(),
        ),
        Provider<FaceDetectionRepository>(
          create: (context) => FaceDetectionRepositoryImpl(context.read()),
        ),
        Provider<LocationLocalDataSource>(
          create: (_) => LocationLocalDataSourceImpl(),
        ),
        Provider<NearbyRemoteDataSource>(
          create: (_) => fakeMode
              ? NearbyRemoteDataSourceFakeImpl()
              : NearbyRemoteDataSourceImpl(),
        ),
        Provider<LocationRepository>(
          create: (context) => LocationRepositoryImpl(context.read()),
        ),
        Provider<NearbyRepository>(
          create: (context) => NearbyRepositoryImpl(context.read()),
        ),
        Provider<ProfileLocalDataSource>(
          create: (_) => ProfileLocalDataSourceImpl(),
        ),
        Provider<ProfileRepository>(
          create: (context) => ProfileRepositoryImpl(context.read()),
        ),
        Provider<PaywallLocalDataSource>(
          create: (_) => PaywallLocalDataSourceImpl(),
        ),
        Provider<PaywallRemoteDataSource>(
          create: (_) => fakeMode
              ? PaywallRemoteDataSourceFakeImpl()
              : PaywallRemoteDataSourceImpl(),
        ),
        Provider<PaywallRepository>(
          create: (context) =>
              PaywallRepositoryImpl(context.read(), context.read()),
        ),
        // Il negozio (acquisti in-app dello sblocco) non dipende da
        // `fakeMode` ma da `StoreConfig.mode`: simulato in debug finché i
        // pagamenti veri sono spenti, "non disponibile" in release senza
        // configurazione — mai uno sblocco gratuito. Creato **subito**
        // (`lazy: false`): il negozio ripresenta all'avvio gli acquisti non
        // completati, e il plugin vuole che lo si ascolti da subito.
        Provider<StoreBillingDataSource>(
          lazy: false,
          create: (_) => switch (StoreConfig.mode) {
            StoreMode.fake => StoreBillingDataSourceFakeImpl(),
            StoreMode.real => StoreBillingDataSourceImpl(
              productId: StoreConfig.unlockProductIdFor(defaultTargetPlatform),
            ),
            StoreMode.unavailable => StoreBillingDataSourceImpl(
              productId: null,
            ),
          },
        ),
        Provider<StoreRepository>(
          create: (context) => StoreRepositoryImpl(context.read()),
        ),
        // Uno solo, condiviso dai tre use case d'acquisto: così lo stesso
        // acquisto non viene mai riscattato due volte in parallelo.
        Provider<RedeemStorePurchaseUseCase>(
          create: (context) => RedeemStorePurchaseUseCase(
            paywallRepository: context.read(),
            storeRepository: context.read(),
          ),
        ),
        Provider<EncounterRemoteDataSource>(
          create: (_) => fakeMode
              ? EncounterRemoteDataSourceFakeImpl()
              : EncounterRemoteDataSourceImpl(),
        ),
        Provider<EncounterRepository>(
          create: (context) => EncounterRepositoryImpl(context.read()),
        ),
        Provider<ChatRemoteDataSource>(
          create: (_) => fakeMode
              ? ChatRemoteDataSourceFakeImpl()
              : ChatRemoteDataSourceImpl(),
        ),
        Provider<ChatRepository>(
          create: (context) => ChatRepositoryImpl(context.read()),
        ),
        Provider<SafetyRemoteDataSource>(
          create: (_) => fakeMode
              ? SafetyRemoteDataSourceFakeImpl()
              : SafetyRemoteDataSourceImpl(),
        ),
        Provider<BlockedPeopleLocalDataSource>(
          create: (_) => BlockedPeopleLocalDataSourceImpl(),
        ),
        Provider<SafetyRepository>(
          create: (context) =>
              SafetyRepositoryImpl(context.read(), context.read()),
        ),
        Provider<SettingsLocalDataSource>(
          create: (_) => SettingsLocalDataSourceImpl(),
        ),
        Provider<SettingsRepository>(
          create: (context) => SettingsRepositoryImpl(context.read()),
        ),
        // --- presentation: stato UI ---
        ChangeNotifierProvider<ProProfile>(
          create: (context) => ProProfile(
            getProfileUseCase: GetProfileUseCase(context.read()),
            saveProfileUseCase: SaveProfileUseCase(context.read()),
            withdrawProfileUseCase: WithdrawProfileUseCase(
              getCurrentSessionUseCase: GetCurrentSessionUseCase(
                context.read(),
              ),
              endSessionUseCase: _endSessionUseCase(context),
              deleteProfileUseCase: DeleteProfileUseCase(context.read()),
            ),
          ),
        ),
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
            watchSessionClosedByServerUseCase:
                WatchSessionClosedByServerUseCase(context.read()),
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
            watchSessionClosedByServerUseCase:
                WatchSessionClosedByServerUseCase(context.read()),
          ),
        ),
        ChangeNotifierProvider<ProNearby>(
          create: (context) => ProNearby(
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
            openAppSettingsUseCase: OpenAppSettingsUseCase(context.read()),
            watchBlockedPeopleUseCase: WatchBlockedPeopleUseCase(
              context.read(),
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
        ChangeNotifierProvider<ProSettings>(
          create: (context) => ProSettings(
            getLanguageUseCase: GetLanguageUseCase(context.read()),
            setLanguageUseCase: SetLanguageUseCase(context.read()),
            getThemeModeUseCase: GetThemeModeUseCase(context.read()),
            setThemeModeUseCase: SetThemeModeUseCase(context.read()),
            getFakeModeUseCase: GetFakeModeUseCase(
              context.read(),
              isAvailable: fakeModeAvailable,
            ),
            setFakeModeUseCase: SetFakeModeUseCase(
              context.read(),
              isAvailable: fakeModeAvailable,
            ),
          ),
        ),
      ],
      child: Consumer<ProSettings>(
        builder: (context, proSettings, _) => MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context)!.app_title,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: proSettings.themeMode,
          locale: proSettings.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Sopra ogni pagina: gli avvisi una tantum (connessione,
          // richieste, sicurezza, sblocco scaduto) e la pagina del match,
          // che si apre e si chiude da sola seguendo
          // `ProEncounters.activeMatch`.
          home: const CmpConnectionNoticeListener(
            child: CmpEncounterNoticeListener(
              child: CmpSafetyNoticeListener(
                child: CmpUnlockExpiredListener(
                  child: CmpMatchGate(child: UiHome()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
