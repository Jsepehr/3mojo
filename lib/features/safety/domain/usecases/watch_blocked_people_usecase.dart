import '../repositories/safety_repository.dart';

/// Azione: chi hai bloccato (o segnalato) in questa sessione — subito
/// l'insieme attuale, poi a ogni cambiamento. Serve a nascondere quelle
/// persone **subito** ("Vicinanze", richieste, match), senza aspettare lo
/// snapshot del server che lo farà comunque. Vuoto dopo End.
class WatchBlockedPeopleUseCase {
  const WatchBlockedPeopleUseCase(this._repository);

  final SafetyRepository _repository;

  Stream<Set<String>> call() => _repository.watchBlockedPersonIds();
}
