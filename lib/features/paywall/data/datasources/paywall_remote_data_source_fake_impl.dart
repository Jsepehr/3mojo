import 'package:uuid/uuid.dart';

import '/core/config/store_config.dart';
import '/core/errors/exceptions.dart';
import '../../domain/entities/store_purchase.dart';
import '../models/fake_store_receipt.dart';
import '../models/store_purchase_model.dart';
import 'paywall_remote_data_source.dart';

/// Implementazione **finta** (nessuna rete): fa la parte del server — accetta
/// solo le ricevute del negozio simulato (`FakeStoreReceipt` integra, del
/// prodotto finto), riscatta ogni transazione **una volta** (la stessa
/// ridà lo stesso token finché vale) e tiene gli sblocchi in memoria con
/// l'orologio del dispositivo — qui va bene, dato che in modalità finta
/// non c'è nessun vero pagamento da proteggere.
class PaywallRemoteDataSourceFakeImpl implements PaywallRemoteDataSource {
  /// 2 ore come quello vero; per provare il timer e la scadenza senza
  /// aspettare, `flutter run --dart-define=FAKE_UNLOCK_MINUTES=3` lo
  /// accorcia (vale solo per questo finto: modalità finta e demo).
  static const _unlockDuration = _fakeUnlockMinutes > 0
      ? Duration(minutes: _fakeUnlockMinutes)
      : Duration(hours: 2);
  static const _fakeUnlockMinutes = int.fromEnvironment('FAKE_UNLOCK_MINUTES');

  final Map<String, DateTime> _unlockedAtByToken = {};
  final Map<String, String> _tokenByTransaction = {};

  @override
  Future<UnlockGrant> redeemPurchase(StorePurchaseModel purchase) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final receipt = FakeStoreReceipt.decode(purchase.verificationData);
    if (purchase.platform != StorePlatform.fake ||
        receipt == null ||
        receipt.transactionId != purchase.transactionId ||
        receipt.productId != StoreConfig.fakeUnlockProductId) {
      throw const PurchaseRejectedException('invalidReceipt');
    }

    final existing = _tokenByTransaction[receipt.transactionId];
    if (existing != null) {
      final remaining = _remaining(existing);
      if (remaining <= Duration.zero) {
        throw const PurchaseAlreadyRedeemedException();
      }
      return (token: existing, remaining: remaining);
    }
    final token = const Uuid().v4();
    _unlockedAtByToken[token] = DateTime.now();
    _tokenByTransaction[receipt.transactionId] = token;
    return (token: token, remaining: _unlockDuration);
  }

  @override
  Future<Duration> getRemaining(String unlockToken) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return _remaining(unlockToken);
  }

  Duration _remaining(String token) {
    final unlockedAt = _unlockedAtByToken[token];
    if (unlockedAt == null) return Duration.zero;
    final remaining = _unlockDuration - DateTime.now().difference(unlockedAt);
    return remaining > Duration.zero ? remaining : Duration.zero;
  }
}
