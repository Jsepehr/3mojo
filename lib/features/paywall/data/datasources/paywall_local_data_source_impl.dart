import '/core/unlock/unlock_token_store.dart';
import 'paywall_local_data_source.dart';

/// Implementazione **reale**: delega a `UnlockTokenStore` (`core/unlock/`)
/// — lo stesso token, non uno separato, è anche quello che `nearby/` manda
/// al server insieme alla presenza.
class PaywallLocalDataSourceImpl implements PaywallLocalDataSource {
  @override
  Future<String?> readUnlockToken() => UnlockTokenStore.instance.read();

  @override
  Future<void> saveUnlockToken(String token, Duration validFor) =>
      UnlockTokenStore.instance.save(token, validFor);

  @override
  Future<void> clearUnlockToken() => UnlockTokenStore.instance.clear();
}
