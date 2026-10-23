import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/paywall/presentation/paywall_failure_texts.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

/// Ogni esito d'acquisto ha il suo testo tradotto (scelto dal tipo, mai dal
/// `message` tecnico); un annullamento nel negozio non ne ha nessuno.
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    test('[${locale.languageCode}] every purchase failure has its own text, '
        'a cancel has none', () async {
      final l10n = await AppLocalizations.delegate.load(locale);
      final failures = <Failure>[
        const StoreUnavailableFailure(),
        const StorePurchaseFailure('BillingResponse.error'),
        const PurchaseNotVerifiedFailure('invalidReceipt'),
        const PurchaseAlreadyRedeemedFailure(),
        const UnlockNotDeliveredYetFailure(),
      ];

      final texts = [
        for (final f in failures) PaywallFailureTexts.of(l10n, f)!,
      ];

      expect(texts.toSet(), hasLength(failures.length));
      for (final f in failures) {
        expect(texts, isNot(contains(f.message)));
      }
      expect(
        PaywallFailureTexts.of(l10n, const PurchaseCanceledFailure()),
        isNull,
      );
      expect(l10n.pay_price('1,09 €'), contains('1,09 €'));
      expect(l10n.unlock_for_price('1,09 €'), contains('1,09 €'));
      expect(l10n.unlock_dialog_body_price('1,09 €'), contains('1,09 €'));
    });
  }
}
