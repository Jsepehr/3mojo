import 'package:flutter/foundation.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/usecases/withdraw_profile_usecase.dart';
import '../../domain/entities/profile.dart';
import '../../domain/usecases/accept_terms_usecase.dart';
import '../../domain/usecases/get_profile_usecase.dart';
import '../../domain/usecases/save_profile_usecase.dart';

/// Stato UI del profilo: carica quello salvato all'avvio, salva, cancella.
/// Nessuna regola qui — validazioni e consenso vivono in
/// `SaveProfileUseCase`; "da online, prima si chiude la sessione" in
/// `WithdrawProfileUseCase`.
///
/// L'errore è esposto come `Failure` (non come stringa): è la UI
/// (`ProfileLabels.failure`) a scegliere il testo tradotto dal suo tipo.
class ProProfile extends ChangeNotifier {
  ProProfile({
    required GetProfileUseCase getProfileUseCase,
    required SaveProfileUseCase saveProfileUseCase,
    required WithdrawProfileUseCase withdrawProfileUseCase,
    AcceptTermsUseCase? acceptTermsUseCase,
  }) : _getProfileUseCase = getProfileUseCase,
       _saveProfileUseCase = saveProfileUseCase,
       _withdrawProfileUseCase = withdrawProfileUseCase,
       _acceptTermsUseCase =
           acceptTermsUseCase ??
           AcceptTermsUseCase(
             getProfileUseCase: getProfileUseCase,
             saveProfileUseCase: saveProfileUseCase,
           ) {
    _load();
  }

  final GetProfileUseCase _getProfileUseCase;
  final SaveProfileUseCase _saveProfileUseCase;
  final WithdrawProfileUseCase _withdrawProfileUseCase;
  final AcceptTermsUseCase _acceptTermsUseCase;

  bool _isLoading = true;
  Profile? _profile;
  Failure? _failure;

  bool get isLoading => _isLoading;
  Profile? get profile => _profile;
  bool get hasProfile => _profile != null;

  /// Perché l'ultima azione sul profilo non è riuscita, o `null`.
  Failure? get failure => _failure;

  /// Dimentica l'errore precedente (all'apertura della pagina profilo).
  void clearError() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }

  Future<void> _load() async {
    final result = await _getProfileUseCase(const NoParams());
    result.match(
      (failure) => _failure = failure,
      (profile) => _profile = profile,
    );
    _isLoading = false;
    notifyListeners();
  }

  /// `true` se salvato; altrimenti il motivo è in [failure].
  Future<bool> save(Profile profile) async {
    final result = await _saveProfileUseCase(profile);
    final saved = result.match((failure) {
      _failure = failure;
      return false;
    }, (_) => true);

    if (saved) {
      _failure = null;
      // Rilegge quanto salvato davvero (lo use case normalizza alcuni campi).
      final reloaded = await _getProfileUseCase(const NoParams());
      reloaded.match((_) => _profile = profile, (p) => _profile = p);
    }
    notifyListeners();
    return saved;
  }

  /// Accetta i termini d'uso attuali per il profilo già salvato (chiesto
  /// dallo Start ai profili compilati prima che esistessero). `true` se
  /// salvato; altrimenti il motivo è in [failure].
  Future<bool> acceptTerms() async {
    final result = await _acceptTermsUseCase(const NoParams());
    final accepted = result.match((failure) {
      _failure = failure;
      return false;
    }, (_) => true);
    if (accepted) {
      _failure = null;
      final reloaded = await _getProfileUseCase(const NoParams());
      reloaded.match((_) {}, (p) => _profile = p);
    }
    notifyListeners();
    return accepted;
  }

  /// Cancella il profilo; da online chiude prima la sessione. `true` se
  /// cancellato; altrimenti il motivo è in [failure].
  Future<bool> delete() async {
    final result = await _withdrawProfileUseCase(const NoParams());
    final deleted = result.match((failure) {
      _failure = failure;
      return false;
    }, (_) => true);

    if (deleted) {
      _profile = null;
      _failure = null;
    }
    notifyListeners();
    return deleted;
  }
}
