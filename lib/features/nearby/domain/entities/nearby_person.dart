import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '/features/profile/domain/entities/profile.dart';

/// I tre stadi (e soli tre) della probabilità d'incontro: `low` da 1 minuto
/// di permanenza, `medium` da 3, `high` da 5 — calcolato lato server dalla
/// storia di posizione della persona, il client riceve solo il valore già
/// pronto (nessun numero, nessuna via di mezzo continua).
enum MeetingChance { low, medium, high }

/// Una persona vista nella lista "Vicinanze": niente nome (l'app non lo
/// chiede mai), solo una foto, quanto è probabile incontrarla (in base a
/// quanto è rimasta ferma lì), e ciò che ha scelto di mostrare dal proprio
/// profilo: cosa cerca stasera, le lingue, e il genere solo se ha attivato
/// "mostra il mio genere" (altrimenti `null`). Cosa cerca in termini di
/// genere non arriva mai: serve solo al server.
///
/// **Nessuna distanza**: il server non la manda più (un numero preciso a
/// ogni aggiornamento basterebbe a trilaterare la posizione di qualcuno).
/// La lista arriva già ordinata dal server, per fasce di distanza di 25 m
/// (dentro una fascia l'ordine non dice chi è più vicino).
///
/// [id] è uno pseudonimo valido **solo per questo telefono**: la stessa
/// persona ha un id diverso per ognuno che la vede (vedi `Pseudonyms` nel
/// server); serve a mandarle una richiesta, non a riconoscerla altrove.
///
/// [isLocked]: dietro il paywall per chi guarda, deciso **dal server** (che
/// in quel caso non manda nemmeno la foto: [photoBytes] è `null`). Sta
/// sull'entity perché è una regola di business che altri use case leggono
/// (`GetLockedNearbyPeopleUseCase`).
class NearbyPerson extends Equatable {
  const NearbyPerson({
    required this.id,
    required this.meetingChance,
    this.photoBytes,
    this.isLocked = false,
    this.intent,
    this.languages = const [],
    this.visibleGender,
  });

  final String id;

  /// Il selfie già decodificato (JPEG), o `null` se non c'è / è bloccato.
  final Uint8List? photoBytes;
  final MeetingChance meetingChance;
  final bool isLocked;
  final MeetIntent? intent;
  final List<String> languages;
  final Gender? visibleGender;

  @override
  List<Object?> get props => [
    id,
    photoBytes,
    meetingChance,
    isLocked,
    intent,
    languages,
    visibleGender,
  ];
}
