import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../providers/pro_paywall.dart';

/// Banner in cima a "Vicinanze" quando il paywall è attivo: spiega perché
/// alcune foto sono sfocate e apre la conferma d'acquisto. Anche toccare
/// direttamente una foto bloccata apre la stessa conferma — due modi di
/// arrivarci, un solo posto che decide cosa succede.
class CmpPaywallBanner extends StatelessWidget {
  const CmpPaywallBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.the_closest_profiles_are_blurred,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => showPaywallConfirmDialog(context),
              child: Text(l10n.unlock_eur_1),
            ),
          ],
        ),
      ),
    );
  }
}

/// Conferma d'acquisto (finto) — mostra chiaramente che non è un vero
/// addebito, dato che oggi non c'è ancora un prodotto reale registrato
/// negli store (vedi `PurchaseUnlockUseCase`).
Future<void> showPaywallConfirmDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final proPaywall = context.read<ProPaywall>();

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.unlock_nearby_profiles),
      content: Text(l10n.unlock_every_nearby_profile_for_the_next_2_hours_for_eur_1),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await proPaywall.purchase();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.unlocked_for_the_next_2_hours)),
              );
            }
          },
          child: Text(l10n.pay_eur_1),
        ),
      ],
    ),
  );
}
