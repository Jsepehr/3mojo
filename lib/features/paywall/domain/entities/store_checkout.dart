import 'store_purchase.dart';

/// Come è finita la finestra del negozio (annullato ed errori sono
/// `Failure`, non esiti).
sealed class StoreCheckout {
  const StoreCheckout();
}

/// Pagato: da riscattare.
class StoreCheckoutPurchased extends StoreCheckout {
  const StoreCheckoutPurchased(this.purchase);

  final StorePurchase purchase;
}

/// In attesa (contanti su Google Play, approvazione di un genitore su
/// "Chiedi di acquistare"): l'acquisto arriverà più tardi, anche dopo un
/// riavvio, tra quelli da riscattare.
class StoreCheckoutPending extends StoreCheckout {
  const StoreCheckoutPending();
}
