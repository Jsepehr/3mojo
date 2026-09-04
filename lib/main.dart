import 'package:flutter/material.dart';

import 'app.dart';
import 'features/settings/data/datasources/settings_local_data_source_impl.dart';

/// Punto di ingresso: legge la modalità finta salvata prima di costruire
/// l'albero dei provider — `App` la usa per scegliere, una volta per tutte,
/// tra i datasource reali (richiedono il backend `server/`) e quelli finti
/// (nessuna rete). Vedi `ProSettings.setFakeMode`: cambiarla dal drawer
/// richiede di riavviare l'app perché diventi effettiva.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final fakeMode = await SettingsLocalDataSourceImpl().getFakeMode();
  runApp(App(fakeMode: fakeMode));
}
