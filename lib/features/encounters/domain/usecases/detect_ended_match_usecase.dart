import '../entities/encounter_request.dart';
import '../entities/match_end.dart';
import 'find_active_match_usecase.dart';
import 'forget_ended_match_usecase.dart';

/// Azione: confronta le richieste di prima con quelle nuove e dice se il
/// match attivo è finito **non per mano tua** — e in quel caso cancella la
/// sua chat (compone `ForgetEndedMatchUseCase`: la conversazione non
/// sopravvive alla fine dell'incontro).
///
/// Regole:
/// - c'era un match e ora non c'è (o è un altro) → finito dall'altra parte
///   ([MatchEndReason.endedByPartner]);
/// - …tranne se lo stai chiudendo proprio tu ([endingIds]): lo snapshot
///   che lo mostra finito è la conferma della tua azione, non "l'altra
///   persona è uscita" (la chat la cancella già `EndMatchUseCase`);
/// - [sessionRestarted]: il server ha dimenticato la sessione, quindi il
///   match (se c'era) non esiste più comunque
///   ([MatchEndReason.sessionRestarted]), qualunque cosa dica [next].
///
/// `null` = nessun match finito.
class DetectEndedMatchUseCase {
  const DetectEndedMatchUseCase(
    this._forgetEndedMatchUseCase, {
    FindActiveMatchUseCase findActiveMatchUseCase =
        const FindActiveMatchUseCase(),
  }) : _findActiveMatchUseCase = findActiveMatchUseCase;

  final ForgetEndedMatchUseCase _forgetEndedMatchUseCase;
  final FindActiveMatchUseCase _findActiveMatchUseCase;

  Future<MatchEnd?> call({
    required Iterable<EncounterRequest> previous,
    required Iterable<EncounterRequest> next,
    Set<String> locallyEndedIds = const {},
    Set<String> endingIds = const {},
    bool sessionRestarted = false,
  }) async {
    final previousMatch = _findActiveMatchUseCase(
      previous,
      locallyEndedIds: locallyEndedIds,
    );
    if (previousMatch == null) return null;

    final MatchEndReason reason;
    if (sessionRestarted) {
      reason = MatchEndReason.sessionRestarted;
    } else {
      final nextMatch = _findActiveMatchUseCase(
        next,
        locallyEndedIds: locallyEndedIds,
      );
      if (nextMatch?.id == previousMatch.id) return null;
      if (endingIds.contains(previousMatch.id)) return null;
      reason = MatchEndReason.endedByPartner;
    }

    await _forgetEndedMatchUseCase(previousMatch.otherPersonId);
    return MatchEnd(match: previousMatch, reason: reason);
  }
}
