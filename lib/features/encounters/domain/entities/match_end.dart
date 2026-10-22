import 'package:equatable/equatable.dart';

import 'encounter_request.dart';

/// Perché il match attivo non c'è più, quando **non** l'hai chiuso tu.
enum MatchEndReason {
  /// L'altra persona l'ha chiuso, o è andata offline (il server lo segna
  /// finito nello snapshot).
  endedByPartner,

  /// Il server ha dimenticato la sessione durante una caduta: richieste e
  /// match di prima non esistono più lì.
  sessionRestarted,

  /// Hai bloccato (o segnalato) l'altra persona: il match finisce per mano
  /// tua, e il server lo chiude anche dall'altra parte.
  blocked,
}

/// Il match [match] è finito per [reason] (vedi
/// `DetectEndedMatchUseCase`). La sua chat è già stata cancellata.
class MatchEnd extends Equatable {
  const MatchEnd({required this.match, required this.reason});

  final EncounterRequest match;
  final MatchEndReason reason;

  @override
  List<Object?> get props => [match, reason];
}
