import 'dart:async';

import 'package:threemojo_server/src/log.dart';

/// Lo spegnimento ordinato (SIGTERM da `docker stop`/deploy, SIGINT da
/// Ctrl+C), in quest'ordine:
/// 1. smette di accettare nuove connessioni ([stopAccepting]);
/// 2. avvisa i client e chiude i socket ([closeClients]: `sessionClosed`
///    `serverRestart`, codice 1012 — l'app lo racconta all'utente invece di
///    sembrare una caduta di rete);
/// 3. aspetta i salvataggi in corso ([flushers]: stato degli sblocchi, record
///    di moderazione);
/// 4. esce.
///
/// Tutto entro [deadline] (~5 s): scaduto il tempo si esce comunque, senza
/// aspettare ciò che non risponde. Una sola esecuzione, anche con più
/// segnali. [exit] è iniettabile per provarlo senza uccidere il test.
class GracefulShutdown {
  GracefulShutdown({
    required this.stopAccepting,
    required this.closeClients,
    this.flushers = const [],
    this.deadline = const Duration(seconds: 5),
    this.drainDelay = const Duration(milliseconds: 300),
    required this.exit,
  });

  final Future<void> Function() stopAccepting;
  final void Function() closeClients;
  final List<Future<void> Function()> flushers;
  final Duration deadline;

  /// Una breve attesa dopo [closeClients], perché gli ultimi frame (il
  /// `sessionClosed` e la chiusura) escano dai buffer prima dell'uscita.
  final Duration drainDelay;
  final void Function(int code) exit;

  bool _started = false;

  /// `true` dopo il primo segnale.
  bool get started => _started;

  /// Esegue lo spegnimento (la seconda chiamata non fa nulla). Completa
  /// subito prima di [exit].
  Future<void> run(String signal) async {
    if (_started) return;
    _started = true;
    Log.info('shutdown.start', {'signal': signal});

    final timeout = Timer(deadline, () {
      Log.warn('shutdown.deadline_exceeded');
      exit(1);
    });
    try {
      // Si chiude il listener senza aspettare che le connessioni attive
      // finiscano: quelle WebSocket le chiude [closeClients].
      unawaited(stopAccepting().catchError((Object _) {}));
      closeClients();
      if (drainDelay > Duration.zero) await Future<void>.delayed(drainDelay);
      await Future.wait([
        for (final flush in flushers)
          flush().catchError(
            (Object error) => Log.error('shutdown.flush_failed', error: error),
          ),
      ]);
    } catch (error, stackTrace) {
      Log.error('shutdown.failed', error: error, stackTrace: stackTrace);
    } finally {
      timeout.cancel();
    }
    Log.info('shutdown.done');
    exit(0);
  }
}
