import '/core/unlock/unlock_token_store.dart';
import 'paywall_local_data_source.dart';

/// Implementazione **reale**: delega a `UnlockTokenStore` (`core/unlock/`)
/// — lo stesso token, non uno separato, è anche quello che `nearby/` manda
/// al server insieme alla presenza. La demo dichiarata le passa il suo
/// store in memoria ([store], `UnlockTokenStore.inMemory`), condiviso con la
/// sua "Vicinanze" finta.
class PaywallLocalDataSourceImpl implements PaywallLocalDataSource {
  PaywallLocalDataSourceImpl({UnlockTokenStore? store})
    : _store = store ?? UnlockTokenStore.instance;

  final UnlockTokenStore _store;

  @override
  Future<String?> readUnlockToken() => _store.read();

  @override
  Future<void> saveUnlockToken(String token, Duration validFor) =>
      _store.save(token, validFor);

  @override
  Future<void> clearUnlockToken() => _store.clear();
}
