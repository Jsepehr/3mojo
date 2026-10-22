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
/// al paywall. La regola (un terzo delle persone più lontane gratis, minimo
/// 2, le altre bloccate) è **applicata dal server**, che manda già il flag
/// `NearbyPerson.isLocked` — e per chi è bloccato non manda nemmeno la foto.
/// Qui non si ricalcola più nulla (prima il client la duplicava, con il
/// rischio che i due calcoli divergessero): se lo sblocco risulta attivo
/// anche sul telefono (`GetUnlockStatusUseCase`) nessuno è mostrato come
/// bloccato, altrimenti vale il flag del server.
///
/// Puro (nessun repository, nessun I/O): riordina il risultato — tutte le
/// persone gratis prima, quelle bloccate dopo, così chi può essere scelto
/// subito non sta in fondo alla lista dietro a un mucchio di foto sfocate
/// — mantenendo però l'ordine ricevuto dal server (per fasce di distanza)
/// dentro ciascuno dei due gruppi.
class GetLockedNearbyPeopleUseCase {
  const GetLockedNearbyPeopleUseCase();

  List<LockedNearbyPerson> call(
    List<NearbyPerson> people, {
    required bool isUnlocked,
  }) {
    final free = <LockedNearbyPerson>[];
    final locked = <LockedNearbyPerson>[];
    for (final person in people) {
      final isLocked = !isUnlocked && person.isLocked;
      final entry = LockedNearbyPerson(person: person, isLocked: isLocked);
      (isLocked ? locked : free).add(entry);
    }
    return [...free, ...locked];
  }
}
