import 'dart:convert';

import 'package:flutter/widgets.dart';

/// Le foto delle altre persone (selfie ricevuti dal server, o passati tra
/// feature come `EncounterRequest.otherSelfiePath`) arrivano come data URI
/// (`data:image/jpeg;base64,...`), mai come percorso file: niente
/// `dart:io`/`File`, così funziona identico anche sul web. Ritorna `null`
/// se non c'è nessuna foto.
ImageProvider? imageProviderForPhoto(String photoDataUri) {
  if (photoDataUri.isEmpty) return null;
  final base64Part = photoDataUri.split(',').last;
  return MemoryImage(base64Decode(base64Part));
}
