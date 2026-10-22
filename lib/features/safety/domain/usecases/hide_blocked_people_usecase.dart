/// Azione (pura, senza I/O): toglie da una lista ciò che riguarda una
/// persona bloccata in questa sessione. Generica sull'elemento — una
/// persona di "Vicinanze", una richiesta d'incontro… — così `safety/` non
/// dipende dalle feature che la usano: chi chiama dice come leggere lo
/// pseudonimo ([personIdOf]).
///
/// La usano `ProNearby` e `ProEncounters`: la regola "un bloccato non si
/// vede più da nessuna parte" è scritta una volta sola.
class HideBlockedPeopleUseCase {
  const HideBlockedPeopleUseCase();

  List<T> call<T>(
    List<T> items, {
    required Set<String> blockedPersonIds,
    required String Function(T item) personIdOf,
  }) {
    if (blockedPersonIds.isEmpty) return items;
    return [
      for (final item in items)
        if (!blockedPersonIds.contains(personIdOf(item))) item,
    ];
  }
}
