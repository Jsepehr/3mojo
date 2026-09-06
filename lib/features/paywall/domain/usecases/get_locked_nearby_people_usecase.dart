import 'package:equatable/equatable.dart';

import '/features/nearby/domain/entities/nearby_person.dart';

/// Una persona di "Vicinanze" con l'informazione se è visibile gratis o
/// bloccata dal paywall — non tocca l'entity `NearbyPerson`, che resta
/// pura e ignara del paywall (se il paywall venisse rimosso, `nearby/` non
/// cambierebbe di una riga).
class LockedNearbyPerson extends Equatable {
  const LockedNearbyPerson({required this.person, required this.isLocked});

  final NearbyPerson person;
  final bool isLocked;

  @override
  List<Object?> get props => [person, isLocked];
}

/// Azione: quali persone in "Vicinanze" restano gratis e quali sono dietro
/// al paywall. Regola di business: **un terzo del totale**, le **più
/// lontane** — chi è più vicino (più probabile da incontrare davvero) è
/// il contenuto a pagamento, i lontani sono l'assaggio gratuito. Se lo
/// sblocco è attivo (`GetUnlockStatusUseCase`), nessuno è bloccato.
///
/// Puro (nessun repository, nessun I/O): l'ordine della lista passata in
/// ingresso non cambia, ogni persona è solo annotata con `isLocked`.
class GetLockedNearbyPeopleUseCase {
  const GetLockedNearbyPeopleUseCase();

  static const double freeFraction = 1 / 3;

  List<LockedNearbyPerson> call(
    List<NearbyPerson> people, {
    required bool isUnlocked,
  }) {
    if (isUnlocked) {
      return [
        for (final person in people)
          LockedNearbyPerson(person: person, isLocked: false),
      ];
    }

    final byFarthestFirst = [...people]
      ..sort((a, b) => b.distanceMeters.compareTo(a.distanceMeters));
    final freeCount = (people.length * freeFraction).floor();
    final freeIds = byFarthestFirst
        .take(freeCount)
        .map((person) => person.id)
        .toSet();

    return [
      for (final person in people)
        LockedNearbyPerson(person: person, isLocked: !freeIds.contains(person.id)),
    ];
  }
}
