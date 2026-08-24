import 'package:flutter/foundation.dart';

/// Indirizzo del server locale (`server/`, dart_frog) usato dai datasource
/// remoti reali. Di default punta all'host della macchina di sviluppo vista
/// dall'emulatore/simulatore/browser; su un device fisico va sovrascritto
/// con `--dart-define=API_BASE_URL=http://<ip-lan-del-pc>:8080`.
class ApiConfig {
  const ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    // Sul web il browser gira sulla stessa macchina del server: localhost
    // va bene com'è, prima ancora di guardare la piattaforma sottostante
    // (che su web è quella del sistema operativo, non "web" stesso).
    if (kIsWeb) return 'http://localhost:8080';
    // L'emulatore Android vede l'host di sviluppo su 10.0.2.2, non su
    // localhost (che dentro l'emulatore è l'emulatore stesso).
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }
}
