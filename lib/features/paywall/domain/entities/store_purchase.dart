import 'package:equatable/equatable.dart';

/// Il negozio da cui arriva un acquisto.
enum StorePlatform { appStore, googlePlay, fake }

/// Un acquisto **pagato nel negozio ma non ancora completato**: va
/// riscattato dal server (che lo verifica col negozio) e solo dopo
/// completato nel negozio (`StoreRepository.completePurchase`). Finché
/// non è completato il negozio lo ripresenta (riavvio dell'app,
/// riconnessione): così un pagamento non si perde se il server non
/// risponde.
///
/// Lo use case non legge i campi per decidere: li porta dal negozio al
/// server così come sono. [transactionId] identifica l'acquisto (anche per
/// non riscattarlo due volte in parallelo).
class StorePurchase extends Equatable {
  const StorePurchase({
    required this.platform,
    required this.productId,
    required this.transactionId,
    required this.verificationData,
  });

  final StorePlatform platform;
  final String productId;

  /// iOS `transactionId`, Android `orderId` (vuoto negli acquisti di prova
  /// senza ordine), negozio simulato: il suo id.
  final String transactionId;

  /// Ciò che il server manda al negozio per verificarlo: iOS la transazione
  /// firmata (JWS), Android il `purchaseToken`, negozio simulato la ricevuta
  /// finta firmata.
  final String verificationData;

  @override
  List<Object?> get props => [
    platform,
    productId,
    transactionId,
    verificationData,
  ];
}
