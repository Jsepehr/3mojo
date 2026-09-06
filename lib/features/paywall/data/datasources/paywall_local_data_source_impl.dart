import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'paywall_local_data_source.dart';

/// Implementazione **reale**: `shared_preferences`, come `settings/` — a
/// differenza della sessione online, il `deviceId` deve sopravvivere alla
/// chiusura dell'app.
class PaywallLocalDataSourceImpl implements PaywallLocalDataSource {
  static const _deviceIdKey = 'paywall_device_id';

  @override
  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null) return existing;

    final created = const Uuid().v4();
    await prefs.setString(_deviceIdKey, created);
    return created;
  }
}
