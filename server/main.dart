import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/admin_reports_api.dart';
import 'package:threemojo_server/src/moderation_records.dart';
import 'package:threemojo_server/src/payments/payments.dart';

/// Entrypoint personalizzato di Dart Frog: decide se servire HTTPS/WSS o
/// HTTP/WS in chiaro.
///
/// - Con `TLS_CERT_PATH` (catena di certificati PEM) e `TLS_KEY_PATH`
///   (chiave privata PEM) il server parla **solo TLS**: `https://` e
///   `wss://`. È il modo per esporlo direttamente su Internet.
/// - Senza nessuna delle due resta in chiaro, per lo sviluppo locale
///   (`dart_frog dev`, emulatori, device in LAN) — oppure in produzione
///   **solo** dietro un reverse proxy che termina TLS (Caddy, nginx, il load
///   balancer del provider) e che non è raggiungibile dall'esterno in chiaro.
/// - Con una sola delle due, si rifiuta di partire: una configurazione TLS a
///   metà non deve ricadere in silenzio sul chiaro.
///
/// Il client in release accetta solo `https://` (vedi `ApiConfig` in
/// `lib/core/network/api_config.dart`), quindi un server in chiaro senza
/// proxy davanti semplicemente non è raggiungibile dall'app pubblicata.
///
/// All'avvio prepara anche i **record di moderazione** (l'unico dato che il
/// server conserva oltre le sessioni, vedi `ModerationRecordStore`): dice
/// nel log se non verranno salvati (manca `MODERATION_KEY`) o se gli
/// endpoint admin sono spenti (manca `ADMIN_TOKEN`), cancella subito i
/// record più vecchi di 30 giorni e avvia la pulizia periodica.
///
/// E monta i **pagamenti** (`Payments`, da `PAYMENTS_MODE` e credenziali):
/// scrive nel log la modalità (finta = nessun pagamento vero) e ogni
/// piattaforma rimasta spenta per configurazione incompleta.
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) async {
  final certPath = Platform.environment['TLS_CERT_PATH'] ?? '';
  final keyPath = Platform.environment['TLS_KEY_PATH'] ?? '';
  if (certPath.isEmpty != keyPath.isEmpty) {
    throw StateError(
      'TLS configurato a metà: servono sia TLS_CERT_PATH sia TLS_KEY_PATH.',
    );
  }

  await _startModeration();
  _reportPayments();

  if (certPath.isEmpty) return serve(handler, ip, port);
  final securityContext = SecurityContext()
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);
  return serve(handler, ip, port, securityContext: securityContext);
}

Future<void> _startModeration() async {
  final records = ModerationRecordStore.instance;
  final recordsProblem = records.configurationProblem;
  if (recordsProblem != null) stderr.writeln('[moderazione] $recordsProblem');
  final adminProblem = AdminReportsApi.configurationProblem(
    Platform.environment,
  );
  if (adminProblem != null) stderr.writeln('[moderazione] $adminProblem');
  await records.purgeSafely();
  records.startPeriodicPurge();
}

void _reportPayments() {
  final payments = Payments.instance;
  for (final problem in payments.config.problems) {
    stderr.writeln('[pagamenti] $problem');
  }
  final config = payments.config;
  stderr.writeln(
    '[pagamenti] modalità ${config.mode.name}'
    '${config.apple != null ? ', iOS attivo' : ''}'
    '${config.google != null ? ', Android attivo' : ''}'
    '${payments.appleNotifications != null ? ', notifiche Apple attive' : ''}'
    '${payments.googleNotifications != null ? ', notifiche Google attive' : ''}',
  );
}
