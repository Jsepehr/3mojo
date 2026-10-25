import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Un avatar **illustrato** generato sul telefono (PNG): sfondo a gradiente
/// in diagonale e una sagoma stilizzata (testa e spalle) chiara sopra. Mai
/// una foto, mai una persona reale, nessun file né rete: lo usano i
/// datasource finti (persone della demo dichiarata e della modalità finta di
/// sviluppo, il "selfie" della demo) dove il server vero manderebbe un
/// selfie.
///
/// [seed] sceglie i colori (stesso seed → stessi colori); [size] è il lato
/// in pixel. Gli stessi parametri ridanno **la stessa istanza** di byte: la
/// cache delle immagini di Flutter non ridecodifica a ogni nuova lista
/// (come `PhotoBytesCache` per i selfie veri).
Uint8List illustratedAvatarPng(int seed, {int size = 160}) =>
    _cache.putIfAbsent((seed, size), () => _render(seed, size));

final Map<(int, int), Uint8List> _cache = {};

/// Coppie di colori (inizio, fine del gradiente), vivaci e diverse tra loro.
const List<(int, int)> _palette = [
  (0xFF7A59, 0xFFC15E), // corallo → ambra
  (0x5B8DEF, 0x7FE0D0), // blu → acqua
  (0x9B6BFF, 0xF28AC4), // viola → rosa
  (0x34C38F, 0xB8E986), // verde → lime
  (0xF2994A, 0xEB5757), // arancio → rosso
  (0x2D9CDB, 0x9B51E0), // cielo → porpora
];

Uint8List _render(int seed, int size) {
  final (start, end) = _palette[seed.abs() % _palette.length];
  final image = img.Image(width: size, height: size, numChannels: 4);
  final pixel = 1 / size;

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final u = (x + 0.5) / size;
      final v = (y + 0.5) / size;

      // Gradiente in diagonale, dall'alto a sinistra al basso a destra.
      final t = ((u + v) / 2).clamp(0.0, 1.0);
      var r = _lerp(start >> 16 & 0xFF, end >> 16 & 0xFF, t);
      var g = _lerp(start >> 8 & 0xFF, end >> 8 & 0xFF, t);
      var b = _lerp(start & 0xFF, end & 0xFF, t);

      // Sagoma: testa (cerchio) e spalle (ellisse tagliata dal bordo),
      // con il bordo sfumato di un pixel (niente scalini).
      final head = _coverage(
        math.sqrt(_square(u - 0.5) + _square(v - 0.40)) - 0.17,
        pixel,
      );
      final shoulders = _coverage(
        math.sqrt(_square((u - 0.5) / 0.33) + _square((v - 0.98) / 0.30)) - 1,
        pixel / 0.3,
      );
      final cover = math.max(head, shoulders) * 0.88;
      r = r + (255 - r) * cover;
      g = g + (255 - g) * cover;
      b = b + (255 - b) * cover;

      image.setPixelRgba(x, y, r.round(), g.round(), b.round(), 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

double _lerp(int a, int b, double t) => a + (b - a) * t;

double _square(double value) => value * value;

/// Quanto un pixel a distanza [distance] (negativa = dentro) dal bordo di
/// una forma ne è coperto, sfumando su [feather].
double _coverage(double distance, double feather) =>
    (0.5 - distance / feather).clamp(0.0, 1.0);
