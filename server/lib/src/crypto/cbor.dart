import 'dart:convert';
import 'dart:typed_data';

/// Decoder **CBOR** (RFC 8949) minimale: quanto basta per leggere un
/// attestation object di App Attest (una mappa con testo, byte, array) e le
/// chiavi COSE (interi negativi), senza una dipendenza in più.
///
/// Tipi letti: interi senza segno e negativi (fino a 64 bit, come [int]
/// quando ci stanno, altrimenti [FormatException]), stringhe di byte
/// ([Uint8List]), stringhe di testo UTF-8 ([String]), array ([List]),
/// mappe ([Map], chiavi testo o intere), `false`/`true`/`null`.
///
/// Rifiuta con [FormatException] — mai un errore di indice — tutto ciò che
/// qui non serve o che rende ambiguo il contenuto: lunghezze indefinite,
/// tag semantici, numeri in virgola mobile, valori "simple" sconosciuti,
/// chiavi di mappa ripetute, annidamenti oltre [maxDepth], lunghezze che
/// sforano l'input e byte avanzati dopo l'elemento.
class Cbor {
  const Cbor._();

  /// Oltre questa profondità l'input non è un attestation object: si
  /// rifiuta prima di consumare stack.
  static const maxDepth = 16;

  /// Decodifica **un solo** elemento che occupa tutti i [bytes].
  static Object? decode(Uint8List bytes) {
    final reader = _Reader(bytes);
    final value = reader.read(0);
    if (reader.offset != bytes.length) {
      throw const FormatException('CBOR: byte avanzati dopo l\'elemento');
    }
    return value;
  }
}

class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  int _byte() {
    if (offset >= bytes.length) {
      throw const FormatException('CBOR: elemento troncato');
    }
    return bytes[offset++];
  }

  /// L'argomento (lunghezza o valore) codificato nei 5 bit bassi.
  int _argument(int info) {
    if (info < 24) return info;
    final count = switch (info) {
      24 => 1,
      25 => 2,
      26 => 4,
      27 => 8,
      _ => throw const FormatException(
        'CBOR: lunghezza indefinita o riservata non ammessa',
      ),
    };
    if (offset + count > bytes.length) {
      throw const FormatException('CBOR: argomento troncato');
    }
    var value = 0;
    for (var i = 0; i < count; i++) {
      // Oltre 2^53 un intero di Dart compilato in JS perderebbe precisione,
      // e un attestation object non ne ha bisogno.
      if (value > 0x1fffffffffffff >> 8) {
        throw const FormatException('CBOR: intero troppo grande');
      }
      value = (value << 8) | bytes[offset++];
    }
    return value;
  }

  Uint8List _take(int length) {
    if (length < 0 || offset + length > bytes.length) {
      throw const FormatException('CBOR: contenuto troncato');
    }
    final view = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return view;
  }

  Object? read(int depth) {
    if (depth > Cbor.maxDepth) {
      throw const FormatException('CBOR: annidamento eccessivo');
    }
    final initial = _byte();
    final major = initial >> 5;
    final info = initial & 0x1f;
    switch (major) {
      case 0:
        return _argument(info);
      case 1:
        return -1 - _argument(info);
      case 2:
        return Uint8List.fromList(_take(_argument(info)));
      case 3:
        try {
          return utf8.decode(_take(_argument(info)));
        } on FormatException {
          throw const FormatException('CBOR: testo non UTF-8');
        }
      case 4:
        final length = _argument(info);
        // Ogni elemento occupa almeno un byte: una lunghezza oltre i byte
        // rimasti è falsa, inutile allocare.
        if (length > bytes.length - offset) {
          throw const FormatException('CBOR: array troncato');
        }
        return [for (var i = 0; i < length; i++) read(depth + 1)];
      case 5:
        final length = _argument(info);
        if (length * 2 > bytes.length - offset) {
          throw const FormatException('CBOR: mappa troncata');
        }
        final map = <Object, Object?>{};
        for (var i = 0; i < length; i++) {
          final rawKey = read(depth + 1);
          if (rawKey is! String && rawKey is! int) {
            throw const FormatException('CBOR: chiave di mappa non ammessa');
          }
          final key = rawKey!;
          if (map.containsKey(key)) {
            throw const FormatException('CBOR: chiave di mappa ripetuta');
          }
          map[key] = read(depth + 1);
        }
        return map;
      case 6:
        throw const FormatException('CBOR: tag semantici non ammessi');
      default:
        return switch (info) {
          20 => false,
          21 => true,
          22 => null,
          _ => throw const FormatException(
            'CBOR: virgola mobile o valore simple non ammesso',
          ),
        };
    }
  }
}
