import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '/features/profile/domain/entities/profile.dart';
import '/features/session/domain/entities/meet_place.dart';

/// "Chi sei ora": selfie appena scattato + una copia del profilo (letto dal
/// telefono allo Start) + il luogo scelto per questa sessione. Non è un
/// account — nasce a ogni Start e sparisce a ogni End; il profilo resta sul
/// telefono, il server lo vede solo finché si è online.
/// `sessionId` è generato da zero a ogni Start (mai un id fisso legato al
/// device): serve solo a farsi riconoscere dal server finché si resta
/// online, nella connessione persistente `GET /ws`.
///
/// Il selfie vive **solo in memoria** (`selfieBytes`): il file scritto dalla
/// fotocamera viene cancellato appena letto (`SelfieLocalDataSourceImpl`).
/// Sono questi byte che si mostrano in UI, si controllano (volto) e si
/// mandano al server.
class OnlineSession extends Equatable {
  const OnlineSession({
    required this.sessionId,
    required this.selfieBytes,
    required this.profile,
    this.place = MeetPlace.fallback,
  });

  final String sessionId;
  final Uint8List selfieBytes;
  final Profile profile;

  /// Dove ci si trova (scelto allo Start, non cambia da online: per cambiarlo
  /// End/Start). Pubblico come lo era l'intento, tranne `other`; solo in
  /// memoria, sparisce a End.
  final MeetPlace place;

  @override
  List<Object?> get props => [sessionId, selfieBytes, profile, place];
}
