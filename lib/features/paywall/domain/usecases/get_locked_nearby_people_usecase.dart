import 'dart:math' as math;

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
/// **Minimo `minFreeCount` persone gratis** anche se il terzo calcolato
/// sarebbe più corto (liste piccole, dove un terzo arrotonda a 0 o 1) —
/// altrimenti con poche persone in giro il paywall bloccherebbe quasi
/// tutti, un assaggio gratuito troppo misero per far vedere cosa si perde.
///
/// Puro (nessun repository, nessun I/O): riordina il risultato — tutte le
/// persone gratis prima, quelle bloccate dopo, così chi può essere scelto
/// subito non sta in fondo alla lista dietro a un mucchio di foto sfocate
/// — mantenendo però l'ordine relativo ricevuto in ingresso dentro ciascuno
/// dei due gruppi.
class GetLockedNearbyPeopleUseCase {
  const GetLockedNearbyPeopleUseCase();

  static const double freeFraction = 1 / 3;
  static const int minFreeCount = 2;

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
    final freeCount = math.min(
      people.length,
      math.max((people.length * freeFraction).floor(), minFreeCount),
    );
    final freeIds = byFarthestFirst
        .take(freeCount)
        .map((person) => person.id)
        .toSet();

    final free = <LockedNearbyPerson>[];
    final locked = <LockedNearbyPerson>[];
    for (final person in people) {
      final isLocked = !freeIds.contains(person.id);
      final entry = LockedNearbyPerson(person: person, isLocked: isLocked);
      (isLocked ? locked : free).add(entry);
    }

    return [...free, ...locked];
  }
}
