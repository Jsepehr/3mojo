import 'package:equatable/equatable.dart';

/// Lo sblocco come lo vende il negozio in questo momento: quanto costa,
/// **già formattato dal negozio** (valuta e lingua del suo account, es.
/// "1,09 €", "$0.99") — o, col negozio simulato, nessun prezzo del negozio
/// ([isSimulated]: la UI mostra quello configurato, 1 €, e dice che non
/// c'è addebito).
///
/// Nella **demo dichiarata** ([isDemo]) lo sblocco è gratuito e simulato:
/// nessun prezzo, e la UI dice "Demo: nessun pagamento".
class UnlockOffer extends Equatable {
  const UnlockOffer.store(String this.displayPrice)
    : isSimulated = false,
      isDemo = false;

  const UnlockOffer.simulated()
    : displayPrice = null,
      isSimulated = true,
      isDemo = false;

  const UnlockOffer.demo()
    : displayPrice = null,
      isSimulated = true,
      isDemo = true;

  /// `null` per l'offerta simulata e per quella della demo.
  final String? displayPrice;
  final bool isSimulated;
  final bool isDemo;

  @override
  List<Object?> get props => [displayPrice, isSimulated, isDemo];
}
