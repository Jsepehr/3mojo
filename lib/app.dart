import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/chat/data/datasources/chat_local_data_source.dart';
import 'features/chat/data/datasources/chat_local_data_source_impl.dart';
import 'features/chat/data/repositories/chat_repository_impl.dart';
import 'features/chat/domain/repositories/chat_repository.dart';
import 'features/chat/domain/usecases/get_messages_usecase.dart';
import 'features/chat/domain/usecases/get_or_create_conversation_usecase.dart';
import 'features/chat/domain/usecases/send_message_usecase.dart';
import 'features/chat/presentation/providers/pro_chat.dart';
import 'features/encounters/data/datasources/encounter_remote_data_source.dart';
import 'features/encounters/data/datasources/encounter_remote_data_source_impl.dart';
import 'features/encounters/data/repositories/encounter_repository_impl.dart';
import 'features/encounters/domain/repositories/encounter_repository.dart';
import 'features/encounters/domain/usecases/end_match_usecase.dart';
import 'features/encounters/domain/usecases/get_incoming_requests_usecase.dart';
import 'features/encounters/domain/usecases/get_outgoing_requests_usecase.dart';
import 'features/encounters/domain/usecases/respond_to_encounter_request_usecase.dart';
import 'features/encounters/domain/usecases/send_encounter_request_usecase.dart';
import 'features/encounters/presentation/pages/ui_active_match.dart';
import 'features/encounters/presentation/providers/pro_encounters.dart';
import 'features/nearby/data/datasources/location_local_data_source.dart';
import 'features/nearby/data/datasources/location_local_data_source_impl.dart';
import 'features/nearby/data/datasources/nearby_remote_data_source.dart';
import 'features/nearby/data/datasources/nearby_remote_data_source_impl.dart';
import 'features/nearby/data/repositories/location_repository_impl.dart';
import 'features/nearby/data/repositories/nearby_repository_impl.dart';
import 'features/nearby/domain/repositories/location_repository.dart';
import 'features/nearby/domain/repositories/nearby_repository.dart';
import 'features/nearby/domain/usecases/get_current_location_usecase.dart';
import 'features/nearby/domain/usecases/get_nearby_people_usecase.dart';
import 'features/nearby/presentation/providers/pro_nearby.dart';
import 'features/session/data/datasources/session_local_data_source.dart';
import 'features/session/data/datasources/session_local_data_source_impl.dart';
import 'features/session/data/repositories/session_repository_impl.dart';
import 'features/session/domain/repositories/session_repository.dart';
import 'features/session/domain/usecases/end_session_usecase.dart';
import 'features/session/domain/usecases/get_current_session_usecase.dart';
import 'features/session/domain/usecases/start_session_usecase.dart';
import 'features/session/presentation/pages/ui_home.dart';
import 'features/session/presentation/providers/pro_session.dart';
import 'l10n/generated/app_localizations.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SessionLocalDataSource>(
          create: (_) => SessionLocalDataSourceImpl(),
        ),
        Provider<SessionRepository>(
          create: (context) => SessionRepositoryImpl(context.read()),
        ),
        ChangeNotifierProvider<ProSession>(
          create: (context) => ProSession(
            getCurrentSessionUseCase: GetCurrentSessionUseCase(context.read()),
            startSessionUseCase: StartSessionUseCase(context.read()),
            endSessionUseCase: EndSessionUseCase(context.read()),
          ),
        ),
        Provider<LocationLocalDataSource>(
          create: (_) => LocationLocalDataSourceImpl(),
        ),
        Provider<NearbyRemoteDataSource>(
          create: (_) => NearbyRemoteDataSourceImpl(),
        ),
        Provider<LocationRepository>(
          create: (context) => LocationRepositoryImpl(context.read()),
        ),
        Provider<NearbyRepository>(
          create: (context) => NearbyRepositoryImpl(context.read()),
        ),
        ChangeNotifierProvider<ProNearby>(
          create: (context) => ProNearby(
            getNearbyPeopleUseCase: GetNearbyPeopleUseCase(
              getCurrentLocationUseCase: GetCurrentLocationUseCase(
                context.read(),
              ),
              nearbyRepository: context.read(),
            ),
          ),
        ),
        Provider<EncounterRemoteDataSource>(
          create: (_) => EncounterRemoteDataSourceImpl(),
        ),
        Provider<EncounterRepository>(
          create: (context) => EncounterRepositoryImpl(context.read()),
        ),
        ChangeNotifierProvider<ProEncounters>(
          create: (context) => ProEncounters(
            sendEncounterRequestUseCase: SendEncounterRequestUseCase(
              context.read(),
            ),
            getIncomingRequestsUseCase: GetIncomingRequestsUseCase(
              context.read(),
            ),
            getOutgoingRequestsUseCase: GetOutgoingRequestsUseCase(
              context.read(),
            ),
            respondToEncounterRequestUseCase: RespondToEncounterRequestUseCase(
              context.read(),
            ),
            endMatchUseCase: EndMatchUseCase(context.read()),
          ),
        ),
        Provider<ChatLocalDataSource>(create: (_) => ChatLocalDataSourceImpl()),
        Provider<ChatRepository>(
          create: (context) => ChatRepositoryImpl(context.read()),
        ),
        ChangeNotifierProvider<ProChat>(
          create: (context) => ProChat(
            getOrCreateConversationUseCase: GetOrCreateConversationUseCase(
              context.read(),
            ),
            getMessagesUseCase: GetMessagesUseCase(context.read()),
            sendMessageUseCase: SendMessageUseCase(context.read()),
          ),
        ),
      ],
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const _MatchGate(child: UiHome()),
      ),
    );
  }
}

/// Watches for a mutual match anywhere in the app and takes over the whole
/// screen with the active-match page, regardless of what's currently shown.
class _MatchGate extends StatefulWidget {
  const _MatchGate({required this.child});

  final Widget child;

  @override
  State<_MatchGate> createState() => _MatchGateState();
}

class _MatchGateState extends State<_MatchGate> {
  bool _matchScreenOpen = false;

  @override
  Widget build(BuildContext context) {
    final activeMatch = context.watch<ProEncounters>().activeMatch;

    if (activeMatch != null && !_matchScreenOpen) {
      _matchScreenOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => UiActiveMatch(request: activeMatch),
            fullscreenDialog: true,
          ),
        );
        _matchScreenOpen = false;
      });
    }

    return widget.child;
  }
}
