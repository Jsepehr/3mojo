import 'dart:convert';
import 'dart:typed_data';

/// Controlla e ripulisce il selfie che il client manda con la prima
/// presenza della sessione, prima di ridistribuirlo agli altri.
///
/// - Deve essere un **JPEG** vero (marcatori SOI/EOI), non un file
///   qualsiasi spacciato per foto: chi lo riceve lo passa al decoder di
///   immagini del proprio telefono.
/// - Dimensione massima [maxBytes] (decodificato): il client lo
///   ridimensiona prima di mandarlo, un selfie enorme è un abuso (banda e
///   RAM di tutti quelli che lo ricevono).
/// - Toglie i segmenti di metadati (APP1 = EXIF/XMP, che può contenere la
///   posizione GPS dello scatto e il modello del telefono; APP13 = IPTC;
///   commenti; segmenti proprietari dei produttori): agli altri arriva solo
///   l'immagine. Restano APP0 (JFIF), APP2 (profilo colore ICC) e APP14
///   (Adobe, serve a decodificare i colori correttamente).
///
/// Il server non decodifica i pixel: non sa né vuole sapere cosa c'è nella
/// foto (nessun dato biometrico lato server), controlla solo la struttura
/// del file.
class SelfieValidator {
  const SelfieValidator._();

  /// ~230 KB decodificati, cioè ~310 KB in base64: sta dentro il limite del
  /// messaggio di presenza (vedi `RealtimeMessageHandler.maxPresenceChars`).
  static const maxBytes = 230 * 1024;

  static const _keptAppMarkers = {0xE0, 0xE2, 0xEE};

  /// Il selfie ripulito, ricodificato in base64, oppure `null` se non è un
  /// JPEG valido o è troppo grande.
  static String? sanitizeBase64(String base64Selfie) {
    final Uint8List bytes;
    try {
      bytes = base64Decode(base64Selfie);
    } on FormatException {
      return null;
    }
    if (bytes.length > maxBytes) return null;

    final stripped = stripMetadata(bytes);
    if (stripped == null) return null;
    return base64Encode(stripped);
  }

  /// Il JPEG senza segmenti di metadati, o `null` se la struttura non è
  /// quella di un JPEG (SOI iniziale, segmenti con lunghezza coerente fino
  /// a SOS, EOI finale).
  static Uint8List? stripMetadata(Uint8List bytes) {
    if (bytes.length < 4) return null;
    if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    if (!_endsWithEoi(bytes)) return null;

    final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
    var offset = 2;
    while (true) {
      if (offset + 4 > bytes.length) return null;
      if (bytes[offset] != 0xFF) return null;
      // Byte di riempimento 0xFF ammessi prima del marcatore.
      var markerOffset = offset + 1;
      while (markerOffset < bytes.length && bytes[markerOffset] == 0xFF) {
        markerOffset++;
      }
      if (markerOffset + 2 >= bytes.length) return null;
      final marker = bytes[markerOffset];
      // Marcatori senza lunghezza (TEM, RSTn) o un secondo SOI/EOI prima
      // dell'immagine: struttura non valida per un selfie.
      if (marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD9) ||
          marker == 0x00) {
        return null;
      }

      final length = (bytes[markerOffset + 1] << 8) | bytes[markerOffset + 2];
      if (length < 2) return null;
      final segmentEnd = markerOffset + 1 + length;
      if (segmentEnd > bytes.length) return null;

      if (marker == 0xDA) {
        // SOS: da qui in poi ci sono i dati compressi dell'immagine, fino
        // alla fine del file — copiati così come sono.
        out.add(Uint8List.sublistView(bytes, markerOffset - 1));
        return out.takeBytes();
      }

      final isMetadata =
          marker == 0xFE || // COM
          (marker >= 0xE1 &&
              marker <= 0xEF &&
              !_keptAppMarkers.contains(marker));
      if (!isMetadata) {
        out.add(Uint8List.sublistView(bytes, markerOffset - 1, segmentEnd));
      }
      offset = segmentEnd;
    }
  }

  /// EOI (`FF D9`) negli ultimi byte: alcuni encoder lasciano qualche byte
  /// di padding dopo la fine, tollerato.
  static bool _endsWithEoi(Uint8List bytes) {
    final start = bytes.length > 34 ? bytes.length - 34 : 2;
    for (var i = bytes.length - 2; i >= start; i--) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) return true;
    }
    return false;
  }
}
