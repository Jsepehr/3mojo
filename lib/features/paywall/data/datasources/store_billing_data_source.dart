import '../../domain/entities/store_checkout.dart';
import '../../domain/entities/store_purchase.dart';
import '../../domain/entities/unlock_offer.dart';

/// Contratto verso il **negozio** (acquisti in-app): App Store / Google Play
/// (`StoreBillingDataSourceImpl`, pacchetto ufficiale `in_app_purchase`) o
/// quello simulato dei build di debug (`StoreBillingDataSourceFakeImpl`).
///
/// Lo sblocco è un prodotto **consumabile**: si può ricomprare dopo che è
/// stato completato ([completePurchase]). Il negozio tiene ogni acquisto
/// pagato e non completato e lo ripresenta (riavvio, riconnessione):
/// [unfinishedPurchases].
abstract class StoreBillingDataSource {
  /// Il prodotto dello sblocco col prezzo del negozio. Lancia
  /// `StoreUnavailableException` se il negozio non c'è o il prodotto non
  /// esiste.
  Future<UnlockOffer> loadUnlockOffer();

  /// Apre la finestra del negozio e aspetta com'è finita. Lancia
  /// `PurchaseCanceledException`, `StorePurchaseException` o
  /// `StoreUnavailableException`.
  Future<StoreCheckout> buyUnlock();

  /// Gli acquisti pagati arrivati fuori da [buyUnlock] (rimasti aperti
  /// dall'esecuzione precedente, pagamento in attesa confermato…). Quelli
  /// arrivati prima che qualcuno ascolti vengono tenuti da parte: **un solo
  /// ascoltatore** (`ProPaywall`, per tutta la vita dell'app).
  Stream<StorePurchase> get unfinishedPurchases;

  /// Gli acquisti pagati visti in questa esecuzione e non ancora completati.
  List<StorePurchase> get knownUnfinishedPurchases;

  /// Completa (consuma) l'acquisto nel negozio. Lancia
  /// `StorePurchaseException` se il negozio non lo accetta (lo
  /// ripresenterà).
  Future<void> completePurchase(StorePurchase purchase);
}
