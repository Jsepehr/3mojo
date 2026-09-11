import '/core/device/device_id_provider.dart';
import 'paywall_local_data_source.dart';

/// Implementazione **reale**: delega a `DeviceIdProvider` (`core/device/`)
/// — lo stesso id, non uno separato, è anche quello che `nearby/` manda al
/// server insieme alla presenza, per lo stesso dispositivo.
class PaywallLocalDataSourceImpl implements PaywallLocalDataSource {
  @override
  Future<String> getOrCreateDeviceId() =>
      DeviceIdProvider.instance.getOrCreateDeviceId();
}
