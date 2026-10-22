import 'package:uuid/uuid.dart';

import 'paywall_remote_data_source.dart';

/// Implementazione **finta** (nessuna rete): emette token e tiene gli
/// sblocchi in memoria nel processo dell'app, con l'orologio del
/// dispositivo — qui va bene, dato che in modalità finta non c'è nessun vero
/// pagamento da proteggere.
class PaywallRemoteDataSourceFakeImpl implements PaywallRemoteDataSource {
  static const _unlockDuration = Duration(hours: 2);

  final Map<String, DateTime> _unlockedAtByToken = {};

  @override
  Future<UnlockGrant> purchase() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final token = const Uuid().v4();
    _unlockedAtByToken[token] = DateTime.now();
    return (token: token, remaining: _unlockDuration);
  }

  @override
  Future<Duration> getRemaining(String unlockToken) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final unlockedAt = _unlockedAtByToken[unlockToken];
    if (unlockedAt == null) return Duration.zero;
    final remaining = _unlockDuration - DateTime.now().difference(unlockedAt);
    return remaining > Duration.zero ? remaining : Duration.zero;
  }
}
