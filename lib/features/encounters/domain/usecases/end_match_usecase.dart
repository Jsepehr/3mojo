import '../repositories/encounter_repository.dart';

/// Azione: termina volontariamente un match attivo (irreversibile) —
/// fire-and-forget.
class EndMatchUseCase {
  const EndMatchUseCase(this._repository);

  final EncounterRepository _repository;

  void call(String requestId) => _repository.endMatch(requestId);
}
