import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/check_selfie_has_face_usecase.dart';
import '/features/session/domain/usecases/end_session_usecase.dart';
import '/features/session/domain/usecases/flip_selfie_usecase.dart';
import '/features/session/domain/usecases/start_session_usecase.dart';
import '/features/session/domain/usecases/take_selfie_usecase.dart';
import '/features/session/domain/usecases/watch_session_usecase.dart';

/// Stato di sessione: online/offline, dati della sessione corrente, e lo
/// stato del wizard di Start (selfie, errori). `UiHome` osserva `isOnline`
/// per decidere quale schermata mostrare.
///
/// La sessione segue **il ciclo di vita vero** (`WatchSessionUseCase`), non
/// solo i propri Start/End: se la sessione finisce da un'altra parte (es.
/// cancellando il profilo da online, `WithdrawProfileUseCase`) la home torna
/// offline da sola. Mentre si è online impedisce anche lo standby dello
/// schermo (`WakelockPlus`) — si guarda il telefono in mano camminando, non
/// ha senso che si spenga da solo; da offline torna al comportamento
/// normale e le foto decodificate per lo schermo vengono tolte dalla RAM.
///
/// L'errore è esposto come `Failure` (non come stringa): è la UI
/// (`SessionFailureTexts`) a scegliere il testo tradotto dal suo tipo.
class ProSession extends ChangeNotifier {
  ProSession({
    required WatchSessionUseCase watchSessionUseCase,
    required StartSessionUseCase startSessionUseCase,
    required EndSessionUseCase endSessionUseCase,
    required CheckSelfieHasFaceUseCase checkSelfieHasFaceUseCase,
    required TakeSelfieUseCase takeSelfieUseCase,
    required FlipSelfieUseCase flipSelfieUseCase,
  }) : _startSessionUseCase = startSessionUseCase,
       _endSessionUseCase = endSessionUseCase,
       _checkSelfieHasFaceUseCase = checkSelfieHasFaceUseCase,
       _takeSelfieUseCase = takeSelfieUseCase,
       _flipSelfieUseCase = flipSelfieUseCase {
    _sessionSubscription = watchSessionUseCase().listen(_onSession);
  }

  final StartSessionUseCase _startSessionUseCase;
  final EndSessionUseCase _endSessionUseCase;
  final CheckSelfieHasFaceUseCase _checkSelfieHasFaceUseCase;
  final TakeSelfieUseCase _takeSelfieUseCase;
  final FlipSelfieUseCase _flipSelfieUseCase;

  late final StreamSubscription<OnlineSession?> _sessionSubscription;
  bool _isLoading = true;
  bool _isEnding = false;
  OnlineSession? _session;
  Failure? _failure;

  /// Se gli effetti "da online" (wakelock) sono accesi: tenuto a parte da
  /// [_session], che può cambiare sia da [start]/[end] sia dallo stream.
  bool _onlineEffectsOn = false;

  bool get isLoading => _isLoading;

  /// `true` mentre End è in corso: il bottone si disattiva (niente doppio
  /// tap) finché non si è offline.
  bool get isEnding => _isEnding;
  OnlineSession? get session => _session;
  bool get isOnline => _session != null;

  /// Perché l'ultima azione (selfie, Start, End) non è riuscita, o `null`.
  Failure? get failure => _failure;

  /// Dimentica l'errore precedente: all'apertura del wizard e a ogni nuovo
  /// scatto non deve restare a schermo quello di un tentativo vecchio.
  void clearError() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }

  void _onSession(OnlineSession? session) {
    _isLoading = false;
    _apply(session);
    notifyListeners();
  }

  /// Unico punto in cui cambia la sessione: accende/spegne gli effetti
  /// "da online" una volta sola per ogni passaggio, da qualunque parte
  /// arrivi (Start, End o lo stream).
  void _apply(OnlineSession? session) {
    _session = session;
    if (session != null && !_onlineEffectsOn) {
      _onlineEffectsOn = true;
      unawaited(WakelockPlus.enable());
    } else if (session == null && _onlineEffectsOn) {
      _onlineEffectsOn = false;
      unawaited(WakelockPlus.disable());
      // Le foto degli altri (e il proprio selfie) decodificate per lo
      // schermo non devono restare in RAM dopo End.
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    }
  }

  /// Apre la fotocamera. Ritorna il selfie (solo byte, nessun file resta
  /// sul telefono) o `null` se annullato o fallito — in quel caso il motivo
  /// è in [failure].
  Future<Uint8List?> takeSelfie() async {
    _failure = null;
    final result = await _takeSelfieUseCase(const NoParams());
    final bytes = result.match((failure) {
      _failure = failure;
      return null;
    }, (bytes) => bytes);
    notifyListeners();
    return bytes;
  }

  /// Il selfie ribaltato, o `null` se non è riuscito (motivo in [failure]).
  Future<Uint8List?> flipSelfie(Uint8List selfieBytes) async {
    final result = await _flipSelfieUseCase(selfieBytes);
    final flipped = result.match((failure) {
      _failure = failure;
      return null;
    }, (bytes) => bytes);
    notifyListeners();
    return flipped;
  }

  /// Controllo "a caldo" chiamato dal wizard subito dopo lo scatto, per un
  /// feedback immediato — la validazione vera e autorevole resta comunque
  /// dentro `StartSessionUseCase`, chiamata di nuovo al submit finale.
  Future<bool> checkSelfieHasFace(Uint8List selfieBytes) async {
    final result = await _checkSelfieHasFaceUseCase(selfieBytes);
    _failure = result.match((failure) => failure, (_) => null);
    notifyListeners();
    return result.isRight();
  }

  Future<void> start(StartSessionParams params) async {
    final result = await _startSessionUseCase(params);
    result.match((failure) => _failure = failure, (session) {
      _apply(session);
      _failure = null;
    });
    notifyListeners();
  }

  /// Vai offline. Tutta l'orchestrazione (chiusura locale per prima, poi
  /// visibilità, richieste e chat, best-effort e con un tempo massimo) sta
  /// in `EndSessionUseCase`; qui solo lo stato UI. Le altre feature si
  /// fermano e si azzerano da sole sull'evento di fine sessione
  /// (`WatchSessionUseCase`), come questo provider.
  Future<void> end() async {
    if (_isEnding || _session == null) return;
    _isEnding = true;
    notifyListeners();

    final result = await _endSessionUseCase(const NoParams());
    result.match((failure) => _failure = failure, (_) {
      _apply(null);
      _failure = null;
    });
    _isEnding = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionSubscription.cancel();
    super.dispose();
  }
}
