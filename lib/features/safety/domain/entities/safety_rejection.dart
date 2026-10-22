import 'package:equatable/equatable.dart';

/// Quale azione di sicurezza ha rifiutato il server.
enum SafetyAction { block, report }

/// Perché il server ha rifiutato un blocco o una segnalazione (stessi nomi
/// del server). [other] = un motivo che questa versione dell'app non
/// conosce.
enum SafetyRejectionReason {
  /// La persona non c'è più (sessione finita): niente da bloccare.
  unknownPerson,

  /// Il motivo della segnalazione non è nella lista chiusa.
  invalidReason,

  /// Troppe segnalazioni in questa sessione: il blocco vale comunque.
  tooManyReports,
  other,
}

/// Il server ha ricevuto un blocco o una segnalazione e l'ha rifiutata.
class SafetyRejection extends Equatable {
  const SafetyRejection({
    required this.action,
    required this.reason,
    this.personId,
  });

  final SafetyAction action;
  final SafetyRejectionReason reason;
  final String? personId;

  @override
  List<Object?> get props => [action, reason, personId];
}
