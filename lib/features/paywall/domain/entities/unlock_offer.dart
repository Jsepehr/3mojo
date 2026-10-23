import 'package:equatable/equatable.dart';

/// Lo sblocco come lo vende il negozio in questo momento: quanto costa,
/// **già formattato dal negozio** (valuta e lingua del suo account, es.
/// "1,09 €", "$0.99") — o, col negozio simulato, nessun prezzo del negozio
/// ([isSimulated]: la UI mostra quello configurato, 1 €, e dice che non
/// c'è addebito).
class UnlockOffer extends Equatable {
  const UnlockOffer.store(String this.displayPrice) : isSimulated = false;

  const UnlockOffer.simulated() : displayPrice = null, isSimulated = true;

  /// `null` solo per l'offerta simulata.
  final String? displayPrice;
  final bool isSimulated;

  @override
  List<Object?> get props => [displayPrice, isSimulated];
}
