import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
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
import 'features/nearby/presentation/pages/ui_nearby.dart';
import 'features/nearby/presentation/providers/pro_nearby.dart';
import 'features/profile/data/datasources/profile_local_data_source.dart';
import 'features/profile/data/datasources/profile_local_data_source_impl.dart';
import 'features/profile/data/repositories/profile_repository_impl.dart';
import 'features/profile/domain/repositories/profile_repository.dart';
import 'features/profile/domain/usecases/get_my_profile_usecase.dart';
import 'features/profile/domain/usecases/update_profile_usecase.dart';
import 'features/profile/presentation/pages/ui_profile.dart';
import 'features/profile/presentation/providers/pro_profile.dart';
import 'l10n/generated/app_localizations.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
        Provider<ProfileLocalDataSource>(
          create: (_) => ProfileLocalDataSourceImpl(),
        ),
        Provider<ProfileRepository>(
          create: (context) => ProfileRepositoryImpl(context.read()),
        ),
        ChangeNotifierProvider<ProProfile>(
          create: (context) => ProProfile(
            getMyProfileUseCase: GetMyProfileUseCase(context.read()),
            updateProfileUseCase: UpdateProfileUseCase(context.read()),
          ),
        ),
      ],
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const _HomeShell(),
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _selectedIndex = 0;

  static const _pages = [UiNearby(), UiProfile()];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.radar),
            label: l10n.nearbyPageTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person),
            label: l10n.profilePageTitle,
          ),
        ],
      ),
    );
  }
}
