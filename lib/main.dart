import 'package:flutter/material.dart';

import 'app.dart';
import 'core/licenses/app_licenses.dart';
import 'core/usecases/usecase.dart';
import 'features/profile/data/datasources/profile_local_data_source_impl.dart';
import 'features/profile/data/repositories/profile_repository_impl.dart';
import 'features/profile/domain/usecases/wipe_data_from_previous_install_usecase.dart';
import 'features/settings/data/datasources/settings_local_data_source_impl.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/usecases/get_fake_mode_usecase.dart';

/// Punto di ingresso. Prima di costruire l'albero dei provider:
///
/// 0. registra le licenze che la pagina delle licenze non trova da sola
///    (font Manrope incluso nell'app, librerie native Android:
///    `registerAppLicenses`) — i testi si leggono solo se la pagina si apre;
/// 1. al primo avvio dopo un'installazione cancella ciò che l'archivio
///    cifrato ha conservato da un'installazione precedente (su iOS il
///    Keychain sopravvive alla disinstallazione) — prima che qualcuno legga
///    profilo o token di sblocco. Best-effort: se fallisce si riprova al
///    prossimo avvio;
/// 2. legge la modalità finta — `App` la usa per scegliere, una volta per
///    tutte, tra i datasource reali (richiedono il backend `server/`) e
///    quelli finti (nessuna rete). Nei build di release è sempre `false`
///    (`GetFakeModeUseCase`). Cambiarla dal drawer richiede di riavviare
///    l'app perché diventi effettiva.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();

  await WipeDataFromPreviousInstallUseCase(
    ProfileRepositoryImpl(ProfileLocalDataSourceImpl()),
  )(const NoParams());

  final fakeModeResult = await GetFakeModeUseCase(
    SettingsRepositoryImpl(SettingsLocalDataSourceImpl()),
    isAvailable: App.fakeModeAvailable,
  )(const NoParams());
  final fakeMode = fakeModeResult.getOrElse((_) => false);

  runApp(App(fakeMode: fakeMode));
}
