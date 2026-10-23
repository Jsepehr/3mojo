import 'package:flutter/foundation.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/usecases/update_profile_usecase.dart';
import '/features/session/domain/usecases/withdraw_profile_usecase.dart';
import '../../domain/entities/profile.dart';
import '../../domain/usecases/accept_terms_usecase.dart';
import '../../domain/usecases/get_profile_usecase.dart';
import '../../domain/usecases/renew_sensitive_consent_usecase.dart';
import '../../domain/usecases/save_profile_usecase.dart';

/// Stato UI del profilo: carica quello salvato all'avvio, salva, cancella.
/// Nessuna regola qui — validazioni e consenso vivono in
/// `SaveProfileUseCase`; "da online, prima si chiude la sessione" in
/// `UpdateProfileUseCase` (modifiche al dato sensibile) e
/// `WithdrawProfileUseCase` (cancellazione).
///
/// L'errore è esposto come `Failure` (non come stringa): è la UI
/// (`ProfileLabels.failure`) a scegliere il testo tradotto dal suo tipo.
class ProProfile extends ChangeNotifier {
  ProProfile({
    required GetProfileUseCase getProfileUseCase,
    required SaveProfileUseCase saveProfileUseCase,
    required UpdateProfileUseCase updateProfileUseCase,
    required WithdrawProfileUseCase withdrawProfileUseCase,
    AcceptTermsUseCase? acceptTermsUseCase,
    RenewSensitiveConsentUseCase? renewSensitiveConsentUseCase,
  }) : _getProfileUseCase = getProfileUseCase,
       _updateProfileUseCase = updateProfileUseCase,
       _withdrawProfileUseCase = withdrawProfileUseCase,
       _acceptTermsUseCase =
           acceptTermsUseCase ??
           AcceptTermsUseCase(
             getProfileUseCase: getProfileUseCase,
             saveProfileUseCase: saveProfileUseCase,
           ),
       _renewSensitiveConsentUseCase =
           renewSensitiveConsentUseCase ??
           RenewSensitiveConsentUseCase(
             getProfileUseCase: getProfileUseCase,
             saveProfileUseCase: saveProfileUseCase,
           ) {
    _load();
  }

  final GetProfileUseCase _getProfileUseCase;
  final UpdateProfileUseCase _updateProfileUseCase;
  final WithdrawProfileUseCase _withdrawProfileUseCase;
  final AcceptTermsUseCase _acceptTermsUseCase;
  final RenewSensitiveConsentUseCase _renewSensitiveConsentUseCase;

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

  /// Se salvare [profile] adesso chiuderebbe prima la sessione (modifica al
  /// dato sensibile da online): la pagina lo chiede prima di salvare.
  Future<bool> saveEndsSession(Profile profile) =>
      _updateProfileUseCase.endsSession(profile);

  /// `true` se salvato; altrimenti il motivo è in [failure]. Da online, se
  /// cambia il dato sensibile, chiude prima la sessione
  /// (`UpdateProfileUseCase`).
  Future<bool> save(Profile profile) async {
    final result = await _updateProfileUseCase(profile);
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

  /// Riconferma il consenso al dato sensibile per il testo attuale (chiesto
  /// dallo Start a chi aveva acconsentito a una versione precedente). `true`
  /// se salvato; altrimenti il motivo è in [failure].
  Future<bool> renewSensitiveConsent() async {
    final result = await _renewSensitiveConsentUseCase(const NoParams());
    final renewed = result.match((failure) {
      _failure = failure;
      return false;
    }, (_) => true);
    if (renewed) {
      _failure = null;
      final reloaded = await _getProfileUseCase(const NoParams());
      reloaded.match((_) {}, (p) => _profile = p);
    }
    notifyListeners();
    return renewed;
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
