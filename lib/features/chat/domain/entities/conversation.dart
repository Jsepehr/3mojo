import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// La chat con una persona con cui hai fatto match. Dura finché nessuno
/// dei due la termina esplicitamente — nessuna scadenza a tempo.
/// [otherPersonId] è lo pseudonimo dell'altra persona valido solo su questo
/// telefono (lo stesso di `EncounterRequest.otherPersonId`).
class Conversation extends Equatable {
  const Conversation({
    required this.id,
    required this.otherPersonId,
    this.otherSelfieBytes,
  });

  final String id;
  final String otherPersonId;

  /// Il selfie dell'altra persona già decodificato, o `null`.
  final Uint8List? otherSelfieBytes;

  @override
  List<Object?> get props => [id, otherPersonId, otherSelfieBytes];
}
