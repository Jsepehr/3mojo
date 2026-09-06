import 'paywall_remote_data_source.dart';

/// Implementazione **finta** (nessuna rete): tiene lo sblocco in memoria
/// nel processo dell'app, con l'orologio del dispositivo — qui va bene,
/// dato che in modalità finta non c'è nessun vero pagamento da proteggere.
class PaywallRemoteDataSourceFakeImpl implements PaywallRemoteDataSource {
  static const _unlockDuration = Duration(hours: 2);

  final Map<String, DateTime> _unlockedAt = {};

  @override
  Future<void> purchase(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _unlockedAt[deviceId] = DateTime.now();
  }

  @override
  Future<bool> getStatus(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final unlockedAt = _unlockedAt[deviceId];
    if (unlockedAt == null) return false;
    return DateTime.now().difference(unlockedAt) < _unlockDuration;
  }
}
