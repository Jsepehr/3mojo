import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
/// Salvato **cifrato** con `flutter_secure_storage`, con le stesse opzioni del
/// profilo (`ProfileLocalDataSourceImpl`): Keystore su Android, Keychain
/// `first_unlock_this_device` su iOS (escluso da backup e migrazione su un
/// altro iPhone). Finché vale, il token *è* lo sblocco: in chiaro in
/// `shared_preferences` chiunque potesse leggere i file dell'app (o un
/// backup) avrebbe potuto copiarlo e usarlo. Le versioni precedenti lo
/// tenevano proprio lì: al primo accesso viene spostato nello storage
/// cifrato e, **solo dopo che la scrittura cifrata è riuscita**, cancellato
/// (se non riesce resta dov'era e si riprova al prossimo avvio: uno sblocco
/// pagato non si perde per un Keychain momentaneamente illeggibile).
///
/// Vive in `core/` (non dentro `paywall/`) perché serve a due feature che
/// non devono dipendere l'una dall'altra: `paywall/` lo salva dopo
/// l'acquisto e lo usa per chiedere lo stato; `nearby/` lo manda con la
/// presenza, perché il server decida quali selfie mandare in chiaro — e
/// ascolta [changes] per mandarlo subito dopo un acquisto a sessione già
/// avviata.
///
/// La **demo dichiarata** ne usa uno tutto suo, [UnlockTokenStore.inMemory]:
/// lo sblocco simulato della demo vive solo in memoria, non tocca né lo
/// storage cifrato né `shared_preferences`, e sparisce uscendo dalla demo —
/// non diventa mai uno sblocco vero.
class UnlockTokenStore {
  UnlockTokenStore._({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage,
      _inMemoryOnly = false;

  /// Solo in memoria, per la demo dichiarata (`DemoScope`): niente disco,
  /// niente migrazione delle versioni vecchie.
  UnlockTokenStore.inMemory()
    : _storage = _defaultStorage,
      _inMemoryOnly = true;

  /// Solo per i test: uno storage cifrato diverso (es. uno che fallisce).
  @visibleForTesting
  factory UnlockTokenStore.withStorage(FlutterSecureStorage storage) =>
      UnlockTokenStore._(storage: storage);

  static final UnlockTokenStore instance = UnlockTokenStore._();

  static const _tokenKey = 'paywall_unlock_token';
  static const _expiresAtKey = 'paywall_unlock_expires_at';

  /// Chiave del vecchio identificativo fisso: cancellata al primo accesso,
  /// così sui telefoni che l'avevano non ne resta traccia.
  static const _legacyDeviceIdKey = 'paywall_device_id';

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final FlutterSecureStorage _storage;
  final bool _inMemoryOnly;

  final StreamController<String?> _changes = StreamController.broadcast();

  /// Il caricamento in corso o concluso, condiviso da tutte le chiamate:
  /// due `read()` contemporanee (es. paywall e presenza all'avvio) aspettano
  /// lo stesso caricamento invece di vedere un token ancora `null`.
  Future<void>? _loading;
  String? _token;
  DateTime? _expiresAt;

  /// Emette il nuovo token dopo [save], `null` dopo [clear].
  Stream<String?> get changes => _changes.stream;

  /// Il token, se c'è e non è scaduto secondo l'orologio del telefono. È solo
  /// una pulizia locale: chi decide davvero se vale è sempre il server.
  Future<String?> read() async {
    await _load();
    final expiresAt = _expiresAt;
    if (_token != null &&
        expiresAt != null &&
        DateTime.now().isAfter(expiresAt)) {
      await clear();
    }
    return _token;
  }

  Future<void> save(String token, Duration validFor) async {
    await _load();
    _token = token;
    _expiresAt = DateTime.now().add(validFor);
    _changes.add(token);
    // Se il salvataggio cifrato fallisce lo sblocco vale comunque per
    // quest'esecuzione (è in memoria): segnalarlo come acquisto fallito
    // spingerebbe a pagare di nuovo.
    await _persist(token, _expiresAt!);
  }

  Future<void> clear() async {
    await _load();
    final hadToken = _token != null;
    _token = null;
    _expiresAt = null;
    await _erase();
    if (hadToken) _changes.add(null);
  }

  Future<void> _load() {
    final loading = _loading ??= _doLoad();
    return loading;
  }

  Future<void> _doLoad() async {
    if (_inMemoryOnly) return;
    final legacy = await _readLegacy();
    var secureReadable = true;
    try {
      _token = await _storage.read(key: _tokenKey);
      _expiresAt = DateTime.tryParse(
        await _storage.read(key: _expiresAtKey) ?? '',
      );
    } catch (_) {
      // Keychain/Keystore illeggibile: come se non ci fosse nessun token
      // (al massimo si perde uno sblocco), meglio che bloccare presenza e
      // paywall a ogni chiamata.
      _token = null;
      _expiresAt = null;
      secureReadable = false;
    }

    // Migrazione dalle versioni che lo tenevano in shared_preferences: se
    // il vecchio token vale ancora, lo sblocco pagato non va perso. Le
    // chiavi vecchie si cancellano solo quando non servono più: token già
    // nello storage cifrato, scaduto, o appena scritto lì con successo.
    if (legacy == null) return;
    final legacyStillValid =
        legacy.token != null &&
        legacy.expiresAt != null &&
        DateTime.now().isBefore(legacy.expiresAt!);
    if (!legacyStillValid || _token != null) {
      if (secureReadable) await _removeLegacy();
      return;
    }
    _token = legacy.token;
    _expiresAt = legacy.expiresAt;
    if (await _persist(legacy.token!, legacy.expiresAt!)) {
      await _removeLegacy();
    }
  }

  /// Ciò che le versioni precedenti tenevano in chiaro (token e scadenza),
  /// o `null` se non c'è nulla — nemmeno il vecchio `deviceId` fisso, che
  /// non serve a niente e si cancella sempre subito.
  Future<({String? token, DateTime? expiresAt})?> _readLegacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyDeviceIdKey);
      final token = prefs.getString(_tokenKey);
      final rawExpiresAt = prefs.getString(_expiresAtKey);
      if (token == null && rawExpiresAt == null) return null;
      return (token: token, expiresAt: DateTime.tryParse(rawExpiresAt ?? ''));
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeLegacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_expiresAtKey);
    } catch (_) {
      // Si riprova al prossimo avvio.
    }
  }

  /// `true` se la scrittura cifrata è riuscita.
  Future<bool> _persist(String token, DateTime expiresAt) async {
    if (_inMemoryOnly) return true;
    try {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(
        key: _expiresAtKey,
        value: expiresAt.toIso8601String(),
      );
      return true;
    } catch (_) {
      // Vedi [save]: resta valido in memoria fino alla chiusura dell'app.
      return false;
    }
  }

  Future<void> _erase() async {
    if (_inMemoryOnly) return;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _expiresAtKey);
    } catch (_) {
      // Già tolto dalla memoria; scaduto, al prossimo avvio verrebbe
      // comunque scartato da [read] o rifiutato dal server.
    }
  }
}
