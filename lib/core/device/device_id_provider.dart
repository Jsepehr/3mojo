import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Identificatore anonimo persistente per questa installazione (mai un
/// nome, un'email o un profilo) — generato una volta, salvato in locale,
/// così due controlli separati nel tempo possono riconoscere lo stesso
/// dispositivo senza un vero account.
///
/// Vive in `core/` (non dentro `paywall/`, che l'ha introdotto) perché oggi
/// serve a due feature che non devono dipendere l'una dall'altra solo per
/// condividerlo: `paywall/` lo manda per sapere se questo dispositivo ha
/// sbloccato l'accesso; `nearby/` lo manda insieme alla presenza perché il
/// server possa decidere, per lo stesso motivo, quali selfie mandare in
/// chiaro (vedi `SessionStore.nearbyPeople` lato server) — stesso motivo
/// per cui `RealtimeConnection` vive qui e non dentro una delle due.
/// La chiave in `shared_preferences` resta `paywall_device_id` (non
/// rinominata) per non perdere l'id — e quindi lo sblocco — di chi ha già
/// installato l'app.
class DeviceIdProvider {
  DeviceIdProvider._();

  static final DeviceIdProvider instance = DeviceIdProvider._();

  static const _deviceIdKey = 'paywall_device_id';

  String? _cached;

  Future<String> getOrCreateDeviceId() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null) {
      _cached = existing;
      return existing;
    }

    final created = const Uuid().v4();
    await prefs.setString(_deviceIdKey, created);
    _cached = created;
    return created;
  }
}
