import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/unlock_offer.dart';
import '../../domain/entities/unlock_purchase_result.dart';
import '../paywall_failure_texts.dart';
import '../providers/pro_paywall.dart';

/// Banner in cima a "Vicinanze" quando il paywall è attivo: spiega perché
/// alcune foto sono sfocate e apre la conferma d'acquisto. Anche toccare
/// direttamente una foto bloccata apre la stessa conferma — due modi di
/// arrivarci, un solo posto che decide cosa succede.
///
/// Il bottone mostra il prezzo **del negozio** (formattato da lui); con il
/// negozio simulato quello configurato (1 €). Stati: prezzo in arrivo
/// (indicatore), acquisto in corso nel negozio o in verifica (indicatore,
/// disattivato: niente doppio acquisto), non disponibile ("Non
/// disponibile", disattivato: in release senza negozio il pagamento non
/// può partire). Con un pagamento in attesa (contanti, genitori) sotto al
/// testo c'è "Pagamento in attesa di conferma".
///
/// Store policy: nessun link a pagamenti esterni, e il testo promette solo
/// di **vedere** i profili vicini, non incontri.
class CmpPaywallBanner extends StatelessWidget {
  const CmpPaywallBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proPaywall = context.watch<ProPaywall>();
    final colorScheme = Theme.of(context).colorScheme;
    final onContainer = colorScheme.onPrimaryContainer;
    final isBusy =
        proPaywall.isPurchasing ||
        proPaywall.offerState == UnlockOfferState.loading;
    final isUnavailable = proPaywall.offerState == UnlockOfferState.unavailable;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: onContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.the_closest_profiles_are_blurred,
                    style: TextStyle(color: onContainer),
                  ),
                  if (proPaywall.isPaymentPending) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 16, color: onContainer),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            l10n.payment_pending_confirmation,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: onContainer),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: isBusy || isUnavailable
                  ? null
                  : () => showPaywallConfirmDialog(context),
              child: isBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      isUnavailable
                          ? l10n.unlock_unavailable
                          : _unlockLabel(l10n, proPaywall.offer),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _unlockLabel(AppLocalizations l10n, UnlockOffer? offer) {
    final price = offer?.displayPrice;
    return price == null ? l10n.unlock_eur_1 : l10n.unlock_for_price(price);
  }
}

/// Conferma d'acquisto prima della finestra del negozio: cosa si compra, a
/// quanto (prezzo del negozio), che non si rinnova. Col negozio simulato
/// dice chiaramente che non c'è nessun addebito. "Sbloccato" compare solo
/// se il server ha confermato l'acquisto; un annullamento nel negozio non
/// mostra nulla; gli altri esiti hanno il loro testo
/// (`PaywallFailureTexts`). Senza negozio non si apre: una snackbar dice che
/// gli acquisti non sono disponibili.
Future<void> showPaywallConfirmDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final proPaywall = context.read<ProPaywall>();
  if (proPaywall.isPurchasing) return;
  // Preso ora: a sblocco riuscito il banner (e il suo `context`) sparisce.
  final messenger = ScaffoldMessenger.of(context);

  final offer = proPaywall.offer;
  if (offer == null) {
    if (proPaywall.offerState == UnlockOfferState.unavailable) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.unlock_store_unavailable)),
      );
    }
    return;
  }
  final price = offer.displayPrice;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.unlock_nearby_profiles),
      content: Text(
        price == null
            ? l10n.unlock_every_nearby_profile_for_the_next_2_hours_for_eur_1
            : l10n.unlock_dialog_body_price(price),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            final result = await proPaywall.purchase();
            if (result == null) return;
            final text = switch (result) {
              Right(value: UnlockPurchased()) =>
                l10n.unlocked_for_the_next_2_hours,
              Right(value: UnlockPurchasePending()) =>
                l10n.payment_pending_confirmation,
              Left(value: final failure) => PaywallFailureTexts.of(
                l10n,
                failure,
              ),
            };
            if (text == null) return;
            messenger.showSnackBar(SnackBar(content: Text(text)));
          },
          child: Text(price == null ? l10n.pay_eur_1 : l10n.pay_price(price)),
        ),
      ],
    ),
  );
}
