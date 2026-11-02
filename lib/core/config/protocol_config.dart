import 'package:package_info_plus/package_info_plus.dart';

/// La versione del **protocollo** che parla questa app col server (`/ws` e
/// `/paywall/*`), da non confondere con la versione dell'app: sale solo
/// quando un cambiamento rompe la compatibilità, mai per aggiungere campi.
///
/// **Regola**: client e server ignorano campi e tipi di messaggio che non
/// conoscono. Si può quindi aggiungere un campo al server (o all'app) senza
/// toccare questo numero; lo si alza solo se cambia il *significato* di
/// qualcosa che esiste. Il server accetta la versione attuale N e la
/// precedente N-1 (`ProtocolPolicy`, `server/lib/src/protocol_version.dart`):
/// l'app più vecchia di così riceve `updateRequired` e deve aggiornare.
///
/// Va **allineata** a `ProtocolPolicy.currentVersion` del server quando si
/// rilascia un protocollo nuovo.
class ProtocolConfig {
  const ProtocolConfig._();

  /// Mandata nell'`hello` del WebSocket e nell'header [httpHeader] delle
  /// chiamate HTTP.
  static const int version = 1;

  /// Header HTTP con cui si dichiara [version] (rotte `/paywall/*`).
  static const String httpHeader = 'X-Raen-Protocol';

  /// Codice di chiusura WebSocket con cui il server dice "aggiorna l'app".
  static const int closeCodeUpdateRequired = 4012;

  static String? _appVersion;
  static bool _loading = false;

  /// La versione dell'app (`1.2.3`) se già letta, altrimenti `null`:
  /// informativa, il server la ignora. Mai bloccante — si legge in
  /// background al primo collegamento ([ensureAppVersionLoaded]).
  static String? get appVersion => _appVersion;

  static void ensureAppVersionLoaded() {
    if (_appVersion != null || _loading) return;
    _loading = true;
    PackageInfo.fromPlatform().then(
      (info) {
        final value = info.version.trim();
        _appVersion = value.isEmpty || value.length > 32 ? null : value;
        _loading = false;
      },
      onError: (Object _) {
        // Test, piattaforme senza il plugin: nessuna versione, nessun danno.
        _loading = false;
      },
    );
  }
}
