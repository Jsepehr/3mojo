import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/admin_reports_api.dart';
import 'package:threemojo_server/src/attestation/attestation_gate.dart';
import 'package:threemojo_server/src/graceful_shutdown.dart';
import 'package:threemojo_server/src/log.dart';
import 'package:threemojo_server/src/moderation_records.dart';
import 'package:threemojo_server/src/payments/payments.dart';
import 'package:threemojo_server/src/payments/payments_config.dart';
import 'package:threemojo_server/src/server_environment.dart';
import 'package:threemojo_server/src/session_lifecycle.dart';

/// Entrypoint personalizzato di Dart Frog: decide se servire HTTPS/WSS o
/// HTTP/WS in chiaro, controlla la configurazione e gestisce lo spegnimento.
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
/// **Fail closed** (`ServerEnvironment`): con `RAEN_ENV=production` il
/// server non parte se manca una difesa (pagamenti non `real`,
/// `MODERATION_KEY`, `ADMIN_TOKEN` di almeno 32 caratteri,
/// `PAYMENTS_TRANSACTION_HASH_KEY` fissa) o è accesa una porta da sviluppo
/// (`DEBUG_ENDPOINTS_TOKEN`, `ADMIN_ALLOW_INSECURE_HTTP`,
/// `ATTESTATION_ALLOW_FAKE`). `PAYMENTS_MODE=fake` con TLS o proxy fidato è
/// rifiutato sempre.
///
/// Il client in release accetta solo `https://` (vedi `ApiConfig` in
/// `lib/core/network/api_config.dart`), quindi un server in chiaro senza
/// proxy davanti semplicemente non è raggiungibile dall'app pubblicata.
///
/// All'avvio prepara anche:
/// - i **record di moderazione** (`ModerationRecordStore`): dice nel log se
///   non verranno salvati o se gli endpoint admin sono spenti, cancella i
///   record più vecchi di 30 giorni e avvia la pulizia periodica;
/// - lo **stato degli sblocchi** (`Payments.start`): rimette in RAM gli
///   sblocchi e le transazioni salvate in `DATA_DIR`;
/// - i **pagamenti** (`Payments`, da `PAYMENTS_MODE` e credenziali): la
///   modalità effettiva e ogni piattaforma rimasta spenta;
/// - la **verifica del dispositivo** (`AttestationGate`, da
///   `ATTESTATION_MODE`): non parte con una configurazione che renderebbe
///   `enforce` un rifiuto silenzioso per tutti.
///
/// Con SIGTERM/SIGINT: `GracefulShutdown` (niente nuove connessioni,
/// `sessionClosed` `serverRestart` ai client, socket chiusi con 1012,
/// salvataggi finiti, uscita entro ~5 s).
///
/// Tutto il log è su stderr, una riga JSON per evento, senza dati
/// personali (`Log`).
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) async {
  final env = Platform.environment;
  ServerEnvironment.requireValid(env);

  final certPath = env['TLS_CERT_PATH'] ?? '';
  final keyPath = env['TLS_KEY_PATH'] ?? '';
  if (certPath.isEmpty != keyPath.isEmpty) {
    throw StateError(
      'TLS configurato a metà: servono sia TLS_CERT_PATH sia TLS_KEY_PATH.',
    );
  }

  _checkAttestation();
  await _startModeration();
  await _startPayments();

  final HttpServer server;
  if (certPath.isEmpty) {
    server = await serve(handler, ip, port);
  } else {
    final securityContext = SecurityContext()
      ..useCertificateChain(certPath)
      ..usePrivateKey(keyPath);
    server = await serve(handler, ip, port, securityContext: securityContext);
  }
  _installShutdown(server);
  Log.info('server.started', {
    'port': server.port,
    'tls': certPath.isNotEmpty,
    'production': ServerEnvironment.isProduction(env),
  });
  return server;
}

Future<void> _startModeration() async {
  final records = ModerationRecordStore.instance;
  final recordsProblem = records.configurationProblem;
  if (recordsProblem != null) {
    Log.warn('moderation.config', {'msg': recordsProblem});
  }
  final adminProblem = AdminReportsApi.configurationProblem(
    Platform.environment,
  );
  if (adminProblem != null) Log.warn('admin.config', {'msg': adminProblem});
  await records.purgeSafely();
  records.startPeriodicPurge();
}

Future<void> _startPayments() async {
  final payments = Payments.instance;
  final config = payments.config;
  for (final problem in config.problems) {
    Log.warn('payments.config', {'msg': problem});
  }
  // La modalità scritta è quella **effettiva** (`config.mode`), non
  // dedotta da come è scritta la variabile: così il log non dice "finta"
  // di un server che accetta ricevute vere, né il contrario.
  Log.info('payments.mode', {
    'mode': config.mode.name,
    'fake': config.mode == PaymentsMode.fake,
    'ios': config.apple != null,
    'android': config.google != null,
    'appleNotifications': payments.appleNotifications != null,
    'googleNotifications': payments.googleNotifications != null,
    'persistentState': payments.persistence != null,
  });
  if (config.mode == PaymentsMode.fake) {
    Log.warn('payments.fake_mode', {
      'msg': 'sblocchi con ricevute simulate, nessun pagamento vero',
    });
  }
  if (payments.persistence == null) {
    Log.warn('state.not_persistent', {
      'msg':
          'PAYMENTS_TRANSACTION_HASH_KEY non impostata: sblocchi e '
          'transazioni solo in RAM, un riavvio li perde',
    });
  }
  await payments.start();
}

void _checkAttestation() {
  final gate = AttestationGate.instance;
  final config = gate.config;
  final fatal = config?.fatalProblem;
  if (fatal != null) throw StateError('[attestazione] $fatal');
  if (!gate.isActive) {
    Log.info('attestation.mode', {'mode': 'off'});
    return;
  }
  for (final problem in config?.problems ?? const <String>[]) {
    Log.warn('attestation.config', {'msg': problem});
  }
  Log.info('attestation.mode', {
    'mode': gate.mode.name,
    'platforms': gate.platforms.map((p) => p.name).join(','),
  });
}

void _installShutdown(HttpServer server) {
  final shutdown = GracefulShutdown(
    stopAccepting: () => server.close(),
    closeClients: () {
      SessionLifecycle.instance.shutdownGracefully();
      ModerationRecordStore.instance.stopPeriodicPurge();
    },
    flushers: [Payments.instance.stop, ModerationRecordStore.instance.flush],
    exit: exit,
  );
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    try {
      signal.watch().listen((_) => unawaited(shutdown.run(signal.name)));
    } on SignalException {
      // Piattaforma senza questo segnale (es. SIGTERM su Windows).
    }
  }
}
