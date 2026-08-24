import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Il genere dichiarato dall'utente.
enum Gender { male, female }

/// Il genere che l'utente vuole vedere in "Vicinanze".
enum GenderPreference { male, female, everyone }

/// "Chi sei ora": selfie appena scattato + genere + preferenza. Non è un
/// account — nasce a ogni Start e sparisce a ogni End, nessun dato fisso.
/// `sessionId` è generato da zero a ogni Start (mai un id fisso legato al
/// device): serve solo a farsi riconoscere dal server finché si resta
/// online, in `POST/DELETE /presence` e `GET /nearby`.
///
/// Il selfie vive in due forme: `selfiePath` (un percorso file reale solo
/// su Android/iOS/desktop, usato dal controllo ML Kit) e `selfieBytes` (il
/// contenuto vero e proprio, sempre disponibile su ogni piattaforma — è
/// quello che si mostra in UI e che viene mandato al server, mai `File()`).
class OnlineSession extends Equatable {
  const OnlineSession({
    required this.sessionId,
    required this.selfiePath,
    required this.selfieBytes,
    required this.gender,
    required this.genderPreference,
  });

  final String sessionId;
  final String selfiePath;
  final Uint8List selfieBytes;
  final Gender gender;
  final GenderPreference genderPreference;

  @override
  List<Object?> get props => [
    sessionId,
    selfiePath,
    selfieBytes,
    gender,
    genderPreference,
  ];
}
