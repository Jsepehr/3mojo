import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/entities/connection_status.dart';
import '../../domain/usecases/check_connection_usecase.dart';
import '../../domain/usecases/watch_connection_status_usecase.dart';
import '../../domain/usecases/watch_server_session_restarts_usecase.dart';
import '../../domain/usecases/watch_session_closed_by_server_usecase.dart';

/// Stato del collegamento col server, per la UI: se si sta riconnettendo
/// (indicatore discreto sopra la lista e la chat, senza svuotarle) e un
/// avviso una tantum quando il server ha dimenticato la sessione durante
/// una caduta ([restarts]). Chi tiene uno stato legato alla sessione del
/// server (`ProEncounters`) si azzera da sé ascoltando lo stesso use case.
///
/// Osserva anche il ciclo di vita dell'app (`WidgetsBindingObserver`):
/// - **resumed** (di nuovo in primo piano): `CheckConnectionUseCase` — un
///   ping, e se il server non risponde entro pochi secondi si riconnette
///   subito invece di restare su un socket morto;
/// - **paused** (in background): volutamente **nulla**. Su Android il
///   foreground service della posizione tiene vivi app e socket, e la
///   presenza deve restare visibile anche in tasca; su iOS l'app viene
///   sospesa e il socket resta aperto lato server finché `purgeStale` non
///   lo chiude (90 s senza messaggi). Chiuderlo "pulito senza end" qui
///   farebbe partire subito la grazia (45 s): la sessione morirebbe prima,
///   e su Android si sparirebbe dalla vista di tutti senza motivo.
class ProConnection extends ChangeNotifier with WidgetsBindingObserver {
  ProConnection({
    required WatchConnectionStatusUseCase watchConnectionStatusUseCase,
    required WatchServerSessionRestartsUseCase
    watchServerSessionRestartsUseCase,
    required CheckConnectionUseCase checkConnectionUseCase,
    WatchSessionClosedByServerUseCase? watchSessionClosedByServerUseCase,
  }) : _checkConnectionUseCase = checkConnectionUseCase {
    WidgetsBinding.instance.addObserver(this);
    _statusSubscription = watchConnectionStatusUseCase().listen((status) {
      if (status == _status) return;
      _status = status;
      notifyListeners();
    });
    _restartSubscription = watchServerSessionRestartsUseCase().listen(
      (_) => _restarts.add(null),
    );
    _closureSubscription = watchSessionClosedByServerUseCase?.call().listen(
      (_) => _closures.add(null),
    );
  }

  final CheckConnectionUseCase _checkConnectionUseCase;
  late final StreamSubscription<ConnectionStatus> _statusSubscription;
  late final StreamSubscription<void> _restartSubscription;
  StreamSubscription<void>? _closureSubscription;
  final StreamController<void> _restarts = StreamController.broadcast();
  final StreamController<void> _closures = StreamController.broadcast();
  ConnectionStatus _status = ConnectionStatus.offline;

  ConnectionStatus get status => _status;
  bool get isReconnecting => _status == ConnectionStatus.reconnecting;

  /// Un evento ogni volta che la sessione è ripartita da zero lato server.
  Stream<void> get restarts => _restarts.stream;

  /// Un evento quando il server ha chiuso la sessione dopo le segnalazioni
  /// di più persone (End lo fa `ProSession`).
  Stream<void> get closures => _closures.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkConnectionUseCase();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSubscription.cancel();
    _restartSubscription.cancel();
    _closureSubscription?.cancel();
    _restarts.close();
    _closures.close();
    super.dispose();
  }
}
