import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '/features/profile/domain/entities/profile.dart';
import 'encounter_proposal.dart';

/// Ciclo di vita di una richiesta: in attesa, accettata (= match),
/// rifiutata, annullata (perché ne hai accettata un'altra), o terminata
/// (match chiuso manualmente).
enum EncounterRequestStatus { pending, accepted, declined, cancelled, ended }

/// Una richiesta d'interesse tra due persone, in entrata o in uscita.
///
/// [otherPersonId] è lo stesso pseudonimo con cui l'altra persona compare
/// in "Vicinanze" su questo telefono (vedi `NearbyPerson.id`): valido solo
/// qui, diverso per ognuno che la vede.
class EncounterRequest extends Equatable {
  const EncounterRequest({
    required this.id,
    required this.otherPersonId,
    required this.status,
    this.proposal = EncounterProposal.fallback,
    this.otherSelfieBytes,
    this.otherIntent,
    this.otherLanguages = const [],
    this.otherVisibleGender,
  });

  final String id;
  final String otherPersonId;

  /// Il selfie dell'altra persona già decodificato (JPEG), o `null`: il
  /// server lo manda solo per richieste in attesa o accettate, mai per
  /// quelle finite (rifiutate, annullate, terminate).
  final Uint8List? otherSelfieBytes;
  final EncounterRequestStatus status;

  /// Cosa ha proposto chi ha chiesto (tu, per una richiesta in uscita;
  /// l'altra persona, per una in entrata): la stessa per entrambi i lati,
  /// fissata all'invio.
  final EncounterProposal proposal;

  /// Ciò che l'altra persona mostra dal proprio profilo (come in
  /// "Vicinanze"): cosa cerca, lingue, genere solo se l'ha reso visibile.
  /// Mai chi cerca. Vuoti se la persona non è più online o se la richiesta
  /// è finita.
  final MeetIntent? otherIntent;
  final List<String> otherLanguages;
  final Gender? otherVisibleGender;

  @override
  List<Object?> get props => [
    id,
    otherPersonId,
    otherSelfieBytes,
    status,
    proposal,
    otherIntent,
    otherLanguages,
    otherVisibleGender,
  ];
}
