import 'dart:typed_data';

/// Lettore **DER** minimale (il sottoinsieme di ASN.1 usato da certificati
/// X.509, chiavi PKCS#8 e firme ECDSA): quanto basta per verificare le
/// transazioni firmate da Apple senza una libreria X.509 completa.
///
/// Rifiuta tutto ciò che il DER vieta o che qui non serve: lunghezze
/// indefinite, tag in forma estesa, lunghezze oltre 4 byte, byte avanzati.
/// Un input malformato lancia sempre [FormatException], mai un errore di
/// indice.
class DerNode {
  DerNode._(this.tag, this.encoded, this.content);

  /// Legge **un solo** nodo che occupa tutti i [bytes].
  factory DerNode.parse(Uint8List bytes) {
    final nodes = DerNode.parseAll(bytes);
    if (nodes.length != 1) {
      throw const FormatException('DER: atteso un solo elemento');
    }
    return nodes.single;
  }

  /// Legge tutti i nodi consecutivi in [bytes] (il contenuto di una
  /// SEQUENCE/SET).
  static List<DerNode> parseAll(Uint8List bytes) {
    final nodes = <DerNode>[];
    var offset = 0;
    while (offset < bytes.length) {
      final node = _readAt(bytes, offset);
      nodes.add(node);
      offset += node.encoded.length;
    }
    return nodes;
  }

  static DerNode _readAt(Uint8List bytes, int start) {
    if (start + 2 > bytes.length) {
      throw const FormatException('DER: elemento troncato');
    }
    final tag = bytes[start];
    if (tag & 0x1f == 0x1f) {
      throw const FormatException('DER: tag in forma estesa non supportato');
    }
    var offset = start + 1;
    final first = bytes[offset++];
    int length;
    if (first < 0x80) {
      length = first;
    } else {
      final count = first & 0x7f;
      if (count == 0) {
        throw const FormatException('DER: lunghezza indefinita non ammessa');
      }
      if (count > 4 || offset + count > bytes.length) {
        throw const FormatException('DER: lunghezza non valida');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[offset++];
      }
    }
    final end = offset + length;
    if (end > bytes.length) {
      throw const FormatException('DER: contenuto troncato');
    }
    return DerNode._(
      tag,
      Uint8List.sublistView(bytes, start, end),
      Uint8List.sublistView(bytes, offset, end),
    );
  }

  static const tagBoolean = 0x01;
  static const tagInteger = 0x02;
  static const tagBitString = 0x03;
  static const tagOctetString = 0x04;
  static const tagNull = 0x05;
  static const tagOid = 0x06;
  static const tagUtcTime = 0x17;
  static const tagGeneralizedTime = 0x18;
  static const tagSequence = 0x30;
  static const tagSet = 0x31;

  /// Tag di contesto costruito `[n]` (es. `[0]` versione, `[3]` estensioni).
  static int contextTag(int n) => 0xa0 | n;

  final int tag;

  /// L'elemento intero (tag + lunghezza + contenuto): è ciò che si firma
  /// (es. il `tbsCertificate`).
  final Uint8List encoded;

  /// Solo il contenuto.
  final Uint8List content;

  bool get isConstructed => tag & 0x20 != 0;

  /// I figli di un elemento costruito.
  List<DerNode> get children {
    if (!isConstructed) {
      throw const FormatException('DER: elemento non costruito');
    }
    return parseAll(content);
  }

  DerNode expectTag(int expected) {
    if (tag != expected) {
      throw FormatException(
        'DER: atteso tag 0x${expected.toRadixString(16)}, '
        'trovato 0x${tag.toRadixString(16)}',
      );
    }
    return this;
  }

  /// INTEGER come numero senza segno (le chiavi e le firme sono positive).
  BigInt get asUnsignedInt {
    expectTag(tagInteger);
    var value = BigInt.zero;
    for (final byte in content) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }

  bool get asBool {
    expectTag(tagBoolean);
    if (content.length != 1) throw const FormatException('DER: BOOLEAN');
    return content[0] != 0;
  }

  /// BIT STRING senza bit inutilizzati (chiavi pubbliche, firme).
  Uint8List get asBitStringBytes {
    expectTag(tagBitString);
    if (content.isEmpty || content[0] != 0) {
      throw const FormatException('DER: BIT STRING con bit inutilizzati');
    }
    return Uint8List.sublistView(content, 1);
  }

  /// OBJECT IDENTIFIER in forma puntata (es. `1.2.840.10045.2.1`).
  String get asOid {
    expectTag(tagOid);
    if (content.isEmpty) throw const FormatException('DER: OID vuoto');
    final parts = <int>[];
    var value = 0;
    for (var i = 0; i < content.length; i++) {
      final byte = content[i];
      value = (value << 7) | (byte & 0x7f);
      if (byte & 0x80 == 0) {
        if (parts.isEmpty) {
          final first = value < 80 ? value ~/ 40 : 2;
          parts
            ..add(first)
            ..add(value - first * 40);
        } else {
          parts.add(value);
        }
        value = 0;
      } else if (i == content.length - 1) {
        throw const FormatException('DER: OID troncato');
      }
    }
    return parts.join('.');
  }

  /// UTCTime o GeneralizedTime (sempre in UTC, `Z`), come nei certificati.
  DateTime get asTime {
    final text = String.fromCharCodes(content);
    final match = switch (tag) {
      tagUtcTime => RegExp(r'^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$'),
      tagGeneralizedTime => RegExp(
        r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$',
      ),
      _ => throw const FormatException('DER: atteso un orario'),
    }.firstMatch(text);
    if (match == null) throw FormatException('DER: orario non valido: $text');
    var year = int.parse(match.group(1)!);
    if (tag == tagUtcTime) year += year >= 50 ? 1900 : 2000;
    return DateTime.utc(
      year,
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }
}
