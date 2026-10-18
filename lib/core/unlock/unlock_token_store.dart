import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Il token di sblocco a pagamento emesso dal server (`PaywallStore`), tenuto
/// sul telefono **solo finché vale** (2 ore): così uno sblocco pagato
/// sopravvive a End/Start e alla chiusura dell'app, ma scaduto sparisce.
///
/// Sostituisce il vecchio `deviceId` fisso: quello era generato al primo
/// avvio e mandato per sempre con ogni presenza, quindi legava tra loro
/// tutte le sessioni dello stesso telefono (con posizione, selfie, genere e
/// preferenza). Il token invece esiste solo per chi paga e solo per 2 ore.
/// Chi non paga non ha nessun identificativo.
///
/// Vive in `core/` (non dentro `paywall/`) perché serve a due feature che
/// non devono dipendere l'una dall'altra: `paywall/` lo salva dopo
/// l'acquisto e lo usa per chiedere lo stato; `nearby/` lo manda con la
/// presenza, perché il server decida quali selfie mandare in chiaro — e
/// ascolta [changes] per mandarlo subito dopo un acquisto a sessione già
/// avviata.
class UnlockTokenStore {
  UnlockTokenStore._();

  static final UnlockTokenStore instance = UnlockTokenStore._();

  static const _tokenKey = 'paywall_unlock_token';
  static const _expiresAtKey = 'paywall_unlock_expires_at';

  /// Chiave del vecchio identificativo fisso: cancellata al primo accesso,
  /// così sui telefoni che l'avevano non ne resta traccia.
  static const _legacyDeviceIdKey = 'paywall_device_id';

  final StreamController<String?> _changes = StreamController.broadcast();
  bool _loaded = false;
  String? _token;
  DateTime? _expiresAt;

  /// Emette il nuovo token dopo [save], `null` dopo [clear].
  Stream<String?> get changes => _changes.stream;

  /// Il token, se c'è e non è scaduto secondo l'orologio del telefono. È solo
  /// una pulizia locale: chi decide davvero se vale è sempre il server.
  Future<String?> read() async {
    await _load();
    final expiresAt = _expiresAt;
    if (_token != null && expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      await clear();
    }
    return _token;
  }

  Future<void> save(String token, Duration validFor) async {
    await _load();
    _token = token;
    _expiresAt = DateTime.now().add(validFor);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_expiresAtKey, _expiresAt!.toIso8601String());
    _changes.add(token);
  }

  Future<void> clear() async {
    await _load();
    final hadToken = _token != null;
    _token = null;
    _expiresAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_expiresAtKey);
    if (hadToken) _changes.add(null);
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyDeviceIdKey);
    _token = prefs.getString(_tokenKey);
    _expiresAt = DateTime.tryParse(prefs.getString(_expiresAtKey) ?? '');
  }
}
