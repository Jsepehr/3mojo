import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/watch_session_usecase.dart';
import '../../domain/entities/unlock_offer.dart';
import '../../domain/entities/unlock_purchase_result.dart';
import '../../domain/entities/unlock_status.dart';
import '../../domain/entities/unlock_time_left.dart';
import '../../domain/usecases/get_unlock_offer_usecase.dart';
import '../../domain/usecases/get_unlock_status_usecase.dart';
import '../../domain/usecases/get_unlock_time_left_usecase.dart';
import '../../domain/usecases/purchase_unlock_usecase.dart';
import '../../domain/usecases/retry_unfinished_purchases_usecase.dart';
import '../../domain/usecases/watch_unfinished_purchases_usecase.dart';

/// Un avviso una tantum su uno sblocco arrivato **fuori** dalla finestra
/// d'acquisto (pagamento in attesa confermato, acquisto rimasto in sospeso
/// riscattato al riavvio): la UI lo racconta con una snackbar
/// (`CmpUnlockExpiredListener`).
enum PaywallNotice {
  /// Sbloccato per 2 ore.
  unlocked,

  /// Pagato, ma il server non ha ancora confermato: si riprova da soli.
  deliveryDelayed,
}

/// Lo stato dell'offerta del negozio (il prezzo del bottone).
enum UnlockOfferState { loading, available, unavailable }

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
///
/// **Acquisto** (`PurchaseUnlockUseCase`): negozio vero (App Store / Google
/// Play) o simulato nei build di debug, verificato dal server prima di
/// sbloccare. Il prezzo del bottone è quello del negozio
/// (`GetUnlockOfferUseCase`, [offer]): senza negozio [offerState] è
/// `unavailable` e il pagamento non parte. Gli acquisti pagati e non ancora
/// riscattati (riavvio, pagamento in attesa confermato, server muto) li
/// riscatta `WatchUnfinishedPurchasesUseCase` **dall'avvio**, e
/// `RetryUnfinishedPurchasesUseCase` a ogni Start e a ogni controllo
/// periodico; uno sblocco arrivato così emette un [notices].
class ProPaywall extends ChangeNotifier with WidgetsBindingObserver {
  ProPaywall({
    required WatchSessionUseCase watchSessionUseCase,
    required GetUnlockStatusUseCase getUnlockStatusUseCase,
    required PurchaseUnlockUseCase purchaseUnlockUseCase,
    required GetUnlockOfferUseCase getUnlockOfferUseCase,
    required WatchUnfinishedPurchasesUseCase watchUnfinishedPurchasesUseCase,
    required RetryUnfinishedPurchasesUseCase retryUnfinishedPurchasesUseCase,
    GetUnlockTimeLeftUseCase? getUnlockTimeLeftUseCase,
  }) : _getUnlockStatusUseCase = getUnlockStatusUseCase,
       _purchaseUnlockUseCase = purchaseUnlockUseCase,
       _getUnlockOfferUseCase = getUnlockOfferUseCase,
       _retryUnfinishedPurchasesUseCase = retryUnfinishedPurchasesUseCase,
       _getUnlockTimeLeftUseCase =
           getUnlockTimeLeftUseCase ?? GetUnlockTimeLeftUseCase() {
    WidgetsBinding.instance.addObserver(this);
    _sessionSubscription = watchSessionUseCase().listen(_onSession);
    _unfinishedSubscription = watchUnfinishedPurchasesUseCase().listen(
      _onUnfinishedPurchaseResult,
    );
    _loadOffer();
  }

  static const Duration _statusCheckInterval = Duration(minutes: 5);

  final GetUnlockStatusUseCase _getUnlockStatusUseCase;
  final PurchaseUnlockUseCase _purchaseUnlockUseCase;
  final GetUnlockOfferUseCase _getUnlockOfferUseCase;
  final RetryUnfinishedPurchasesUseCase _retryUnfinishedPurchasesUseCase;
  final GetUnlockTimeLeftUseCase _getUnlockTimeLeftUseCase;

  late final StreamSubscription<OnlineSession?> _sessionSubscription;
  late final StreamSubscription<Either<Failure, UnlockStatus>>
  _unfinishedSubscription;
  final StreamController<void> _expirations = StreamController.broadcast();
  final StreamController<PaywallNotice> _notices = StreamController.broadcast();
  Timer? _statusCheckTimer;
  Timer? _timeLeftTimer;
  bool _isOnline = false;
  UnlockStatus _status = const UnlockStatus.locked();
  UnlockTimeLeft? _timeLeft;
  bool _isPurchasing = false;
  bool _isPaymentPending = false;
  bool _loadingOffer = false;
  UnlockOffer? _offer;
  UnlockOfferState _offerState = UnlockOfferState.loading;
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

  /// La finestra del negozio è aperta o il server sta verificando.
  bool get isPurchasing => _isPurchasing;

  /// Il negozio aspetta il pagamento (contanti, approvazione di un
  /// genitore): lo sblocco arriverà da solo.
  bool get isPaymentPending => _isPaymentPending;

  /// Il prezzo da mostrare (`null` finché non c'è o se non disponibile).
  UnlockOffer? get offer => _offer;

  UnlockOfferState get offerState => _offerState;

  /// Avvisi una tantum su sblocchi arrivati fuori dalla finestra
  /// d'acquisto.
  Stream<PaywallNotice> get notices => _notices.stream;

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
      _retryUnfinishedPurchases();
      if (_offerState == UnlockOfferState.unavailable) _loadOffer();
      _statusCheckTimer = Timer.periodic(_statusCheckInterval, (_) {
        _refresh();
        _retryUnfinishedPurchases();
      });
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

  /// Il prezzo del negozio; se non c'è il bottone resta "Non disponibile"
  /// e si riprova al prossimo Start.
  Future<void> _loadOffer() async {
    if (_loadingOffer) return;
    _loadingOffer = true;
    final result = await _getUnlockOfferUseCase(const NoParams());
    _loadingOffer = false;
    if (_disposed) return;
    result.match(
      (_) {
        _offer = null;
        _offerState = UnlockOfferState.unavailable;
      },
      (offer) {
        _offer = offer;
        _offerState = UnlockOfferState.available;
      },
    );
    notifyListeners();
  }

  /// Compra lo sblocco (vedi `PurchaseUnlockUseCase`). Ritorna l'esito, o
  /// `null` se un acquisto era già in corso e questa chiamata è stata
  /// ignorata (niente doppio acquisto). Un annullamento è
  /// `PurchaseCanceledFailure`: la UI non dice nulla.
  Future<Either<Failure, UnlockPurchaseResult>?> purchase() async {
    if (_isPurchasing) return null;
    _isPurchasing = true;
    notifyListeners();

    final result = await _purchaseUnlockUseCase(const NoParams());
    if (_disposed) return result;

    _isPurchasing = false;
    switch (result) {
      case Right(value: UnlockPurchased(:final status)):
        _isPaymentPending = false;
        _status = status;
      case Right(value: UnlockPurchasePending()):
        _isPaymentPending = true;
      case Left(value: StoreUnavailableFailure()):
        _offer = null;
        _offerState = UnlockOfferState.unavailable;
      case Left():
        break;
    }
    // Avvisa comunque una volta: anche `isPurchasing` è cambiato.
    if (!_updateTimeLeft()) notifyListeners();
    return result;
  }

  /// Un acquisto arrivato fuori dalla finestra d'acquisto è stato
  /// riscattato (o no): lo sblocco si applica e si racconta una volta.
  void _onUnfinishedPurchaseResult(Either<Failure, UnlockStatus> result) {
    if (_disposed) return;
    switch (result) {
      case Right(value: final status):
        _applyDelivered(status);
      case Left(value: UnlockNotDeliveredYetFailure()):
        _notices.add(PaywallNotice.deliveryDelayed);
      case Left():
        // Rifiutato o già usato: nessuno sblocco, niente da raccontare se
        // non che non è più in attesa.
        if (_isPaymentPending) {
          _isPaymentPending = false;
          notifyListeners();
        }
    }
  }

  /// Riprova in silenzio gli acquisti rimasti in sospeso (server muto):
  /// avvisa solo se uno sblocco arriva.
  Future<void> _retryUnfinishedPurchases() async {
    final results = await _retryUnfinishedPurchasesUseCase();
    if (_disposed) return;
    for (final result in results) {
      result.match((_) {}, _applyDelivered);
    }
  }

  void _applyDelivered(UnlockStatus status) {
    _isPaymentPending = false;
    _status = status;
    if (!_updateTimeLeft()) notifyListeners();
    _notices.add(PaywallNotice.unlocked);
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sessionSubscription.cancel();
    _unfinishedSubscription.cancel();
    _statusCheckTimer?.cancel();
    _cancelTimeLeftTimer();
    _expirations.close();
    _notices.close();
    super.dispose();
  }
}
