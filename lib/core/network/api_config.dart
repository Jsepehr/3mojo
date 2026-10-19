import 'package:flutter/foundation.dart';

/// Indirizzo del server (`server/`, dart_frog) usato dai datasource remoti
/// reali.
///
/// - **Debug**: di default punta all'host della macchina di sviluppo vista
///   dall'emulatore/simulatore/browser, in chiaro; su un device fisico va
///   sovrascritto con `--dart-define=API_BASE_URL=http://<ip-lan-del-pc>:8080`.
/// - **Release e profile**: `API_BASE_URL` è obbligatorio e deve essere
///   `https://` (anche profile: è una build ottimizzata che gira su telefoni
///   veri, spesso fuori dalla rete di sviluppo).
///   Tutto ciò che passa di qui — selfie, posizione precisa, genere,
///   preferenza, chat — in chiaro sarebbe leggibile e modificabile da
///   chiunque sulla stessa rete (Wi-Fi pubblici compresi), proprio nei luoghi
///   dove l'app si usa.
class ApiConfig {
  const ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (kReleaseMode || kProfileMode) {
      if (!_override.startsWith('https://')) {
        throw StateError(
          'Build di release senza server sicuro: avvia con '
          '--dart-define=API_BASE_URL=https://<dominio-del-server>.',
        );
      }
      return _override;
    }
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

  /// Stesso host di [baseUrl], ma con schema `ws`/`wss` — per la connessione
  /// persistente condivisa (`GET /ws`, vedi `RealtimeConnection`).
  /// `https://` diventa `wss://`.
  static String get wsBaseUrl => baseUrl.replaceFirst('http', 'ws');
}
