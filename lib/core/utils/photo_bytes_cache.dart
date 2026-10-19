import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// Decodifica i selfie in base64 che arrivano dal server **una sola volta**:
/// lo stesso selfie (stessa stringa) torna come la stessa istanza di
/// `Uint8List`, anche se il server rimanda la lista "vicinanze" o lo
/// snapshot delle richieste molte volte. Un base64 malformato diventa
/// `null` (nessuna foto), mai un'eccezione — né qui né, più tardi, in un
/// `build`.
///
/// Solo in memoria, con un tetto di [maxEntries] foto (le meno usate di
/// recente escono per prime). Da svuotare a fine sessione ([clear]).
class PhotoBytesCache {
  PhotoBytesCache({this.maxEntries = 48});

  final int maxEntries;
  final LinkedHashMap<String, Uint8List> _bytesByBase64 = LinkedHashMap();

  Uint8List? decode(Object? base64Photo) {
    if (base64Photo is! String || base64Photo.isEmpty) return null;

    final cached = _bytesByBase64.remove(base64Photo);
    if (cached != null) {
      _bytesByBase64[base64Photo] = cached; // più recente in coda
      return cached;
    }

    final Uint8List bytes;
    try {
      bytes = base64Decode(base64Photo);
    } on FormatException {
      return null;
    }
    if (bytes.isEmpty) return null;

    _bytesByBase64[base64Photo] = bytes;
    while (_bytesByBase64.length > maxEntries) {
      _bytesByBase64.remove(_bytesByBase64.keys.first);
    }
    return bytes;
  }

  void clear() => _bytesByBase64.clear();
}
