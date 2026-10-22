import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/watch_session_usecase.dart';
import '../../domain/entities/unlock_status.dart';
import '../../domain/entities/unlock_time_left.dart';
import '../../domain/usecases/get_unlock_status_usecase.dart';
import '../../domain/usecases/get_unlock_time_left_usecase.dart';
import '../../domain/usecases/purchase_unlock_usecase.dart';

/// Stato dello sblocco a pagamento: valido per 2 ore dall'acquisto, anche
/// attraverso End/Start e la chiusura dell'app. Fino a quando lo dice il
/// server (`GetUnlockStatusUseCase`: tempo residuo → scadenza sul telefono);
/// quanto resta da mostrare lo decide `GetUnlockTimeLeftUseCase`.
///
/// **Interroga il server solo da online**, guidato dal ciclo di vita della
/// sessione (`WatchSessionUseCase`): a ogni Start controlla lo stato e
/// ricontrolla ogni 5 minuti, riallineando la scadenza; a End il controllo
/// si ferma. Un controllo fallito non cambia nulla (si riprova al prossimo
/// giro): non c'è niente da far fare all'utente.
///
/// **Un solo timer per il tempo residuo**, solo da online e solo con uno
/// sblocco attivo: scatta sul confine del minuto
/// ([UnlockTimeLeft.nextChangeIn]) — mai ogni secondo — e alla scadenza.
/// Ripartendo dall'app in background (dove i timer possono restare fermi)
/// il tempo si ricalcola subito, senza rete.
///
/// Alla fine di uno sblocco che si stava mostrando (scaduto qui, o il server
/// dice che non vale più) emette **un** evento su [expirations] — anche se
/// è finito mentre si era offline, al primo Start dopo — e chiede subito lo
/// stato al server: lui toglie il token e ricalcola chi è bloccato. Qui
/// non si blocca né si sblocca nessuno in contraddizione con lui: le foto
/// tornano bloccate quando il prossimo snapshot di "Vicinanze" lo dice.
class ProPaywall extends ChangeNotifier with WidgetsBindingObserver {
  ProPaywall({
    required WatchSessionUseCase watchSessionUseCase,
    required GetUnlockStatusUseCase getUnlockStatusUseCase,
    required PurchaseUnlockUseCase purchaseUnlockUseCase,
    GetUnlockTimeLeftUseCase? getUnlockTimeLeftUseCase,
    Duration purchaseFeedbackDelay = const Duration(milliseconds: 800),
  }) : _getUnlockStatusUseCase = getUnlockStatusUseCase,
       _purchaseUnlockUseCase = purchaseUnlockUseCase,
       _getUnlockTimeLeftUseCase =
           getUnlockTimeLeftUseCase ?? GetUnlockTimeLeftUseCase(),
       _purchaseFeedbackDelay = purchaseFeedbackDelay {
    WidgetsBinding.instance.addObserver(this);
    _sessionSubscription = watchSessionUseCase().listen(_onSession);
  }

  static const Duration _statusCheckInterval = Duration(minutes: 5);

  final GetUnlockStatusUseCase _getUnlockStatusUseCase;
  final PurchaseUnlockUseCase _purchaseUnlockUseCase;
  final GetUnlockTimeLeftUseCase _getUnlockTimeLeftUseCase;
  final Duration _purchaseFeedbackDelay;

  late final StreamSubscription<OnlineSession?> _sessionSubscription;
  final StreamController<void> _expirations = StreamController.broadcast();
  Timer? _statusCheckTimer;
  Timer? _timeLeftTimer;
  bool _isOnline = false;
  UnlockStatus _status = const UnlockStatus.locked();
  UnlockTimeLeft? _timeLeft;
  bool _isPurchasing = false;
  bool _disposed = false;

  /// Sblocco attivo adesso (ciò che la lista usa per non mostrare nessuno
  /// come bloccato). Aggiornato da online; da offline resta l'ultimo noto
  /// e si ricalcola al prossimo Start.
  bool get isUnlocked => _timeLeft != null;

  /// Quanto resta, da mostrare (`null` se non è attivo).
  UnlockTimeLeft? get timeLeft => _timeLeft;

  /// Fino a quando vale, sull'orologio del telefono (`null` se non è
  /// attivo).
  DateTime? get expiresAt => isUnlocked ? _status.expiresAt : null;

  bool get isPurchasing => _isPurchasing;

  /// Un evento quando uno sblocco che si stava mostrando è finito: la UI
  /// lo racconta una volta (`CmpUnlockExpiredListener`).
  Stream<void> get expirations => _expirations.stream;

  void _onSession(OnlineSession? session) {
    final isOnline = session != null;
    if (isOnline == _isOnline) return;
    _isOnline = isOnline;

    _statusCheckTimer?.cancel();
    _statusCheckTimer = null;
    if (isOnline) {
      // Prima il conto locale (il chip è subito giusto anche senza rete),
      // poi il server.
      _updateTimeLeft();
      _refresh();
      _statusCheckTimer = Timer.periodic(
        _statusCheckInterval,
        (_) => _refresh(),
      );
    } else {
      _cancelTimeLeftTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isOnline) _updateTimeLeft();
  }

  Future<void> _refresh() async {
    final result = await _getUnlockStatusUseCase(const NoParams());
    if (_disposed) return;
    result.match((_) {}, _apply);
  }

  void _apply(UnlockStatus status) {
    final changed = status != _status;
    _status = status;
    if (!_updateTimeLeft() && changed) notifyListeners();
  }

  /// Ricalcola il tempo residuo, emette la fine dello sblocco se c'è stata e
  /// rimette il timer sul prossimo confine del minuto. `true` se ha già
  /// avvisato chi ascolta.
  bool _updateTimeLeft() {
    _cancelTimeLeftTimer();
    final previous = _timeLeft;
    final next = _getUnlockTimeLeftUseCase(_status);
    _timeLeft = next;

    if (next != null && _isOnline) {
      _timeLeftTimer = Timer(next.nextChangeIn, _onTimeLeftTick);
    }
    final ended = previous != null && next == null;
    if (ended) _expirations.add(null);
    if (previous == next) return false;
    notifyListeners();
    return true;
  }

  void _onTimeLeftTick() {
    _timeLeftTimer = null;
    if (_disposed) return;
    _updateTimeLeft();
    // Scaduto sul telefono: sentiamo il server (toglie il token e
    // ricalcola le foto bloccate).
    if (_timeLeft == null && _isOnline) _refresh();
  }

  void _cancelTimeLeftTimer() {
    _timeLeftTimer?.cancel();
    _timeLeftTimer = null;
  }

  /// **Finto per ora**: vedi `PurchaseUnlockUseCase`. Ritorna l'esito
  /// (`Right` = sbloccato), o `null` se un acquisto era già in corso e
  /// questa chiamata è stata ignorata (niente doppio acquisto).
  Future<Either<Failure, Unit>?> purchase() async {
    if (_isPurchasing) return null;
    _isPurchasing = true;
    notifyListeners();

    // Piccola pausa solo per far sentire che "sta succedendo qualcosa" —
    // un vero acquisto in-app avrebbe comunque una latenza simile.
    await Future<void>.delayed(_purchaseFeedbackDelay);

    final result = await _purchaseUnlockUseCase(const NoParams());
    if (_disposed) return result.map((_) => unit);

    _isPurchasing = false;
    result.match((_) {}, (status) => _status = status);
    // Avvisa comunque una volta: anche `isPurchasing` è cambiato.
    if (!_updateTimeLeft()) notifyListeners();
    return result.map((_) => unit);
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sessionSubscription.cancel();
    _statusCheckTimer?.cancel();
    _cancelTimeLeftTimer();
    _expirations.close();
    super.dispose();
  }
}
