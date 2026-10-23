import '/core/errors/failures.dart';
import '/l10n/generated/app_localizations.dart';

/// Il testo (tradotto) di un errore d'acquisto, scelto dal **tipo** — mai
/// da `failure.message`. `null` = non si dice nulla: chi annulla nella
/// finestra del negozio lo sa già.
class PaywallFailureTexts {
  const PaywallFailureTexts._();

  static String? of(AppLocalizations l10n, Failure failure) =>
      switch (failure) {
        PurchaseCanceledFailure() => null,
        StoreUnavailableFailure() => l10n.unlock_store_unavailable,
        PurchaseNotVerifiedFailure() => l10n.purchase_not_verified,
        PurchaseAlreadyRedeemedFailure() => l10n.purchase_already_redeemed,
        UnlockNotDeliveredYetFailure() => l10n.unlock_delivery_delayed,
        _ => l10n.purchase_failed,
      };
}
