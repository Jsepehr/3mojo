import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Le foto delle altre persone (selfie ricevuti dal server) arrivano già
/// decodificate in byte dal layer `data/` (vedi `PhotoBytesCache`): niente
/// `dart:io`/`File`, così funziona identico anche sul web, e niente
/// decodifica base64 a ogni `build`. Ritorna `null` se non c'è nessuna foto.
///
/// Gli stessi byte (la stessa istanza, garantita da `PhotoBytesCache`)
/// danno una `MemoryImage` uguale: la cache delle immagini di Flutter non
/// ridecodifica il JPEG a ogni nuova lista dal server.
ImageProvider? imageProviderForPhoto(Uint8List? photoBytes) {
  if (photoBytes == null || photoBytes.isEmpty) return null;
  return MemoryImage(photoBytes);
}
