import '../repositories/encounter_repository.dart';

/// Azione: manda una richiesta d'interesse a una persona vista in
/// "Vicinanze" — fire-and-forget, l'esito (creata, arrivata all'altro)
/// arriva col prossimo snapshot di `WatchEncounterRequestsUseCase`.
class SendEncounterRequestUseCase {
  const SendEncounterRequestUseCase(this._repository);

  final EncounterRepository _repository;

  void call(String otherPersonId) =>
      _repository.sendRequest(otherPersonId: otherPersonId);
}
