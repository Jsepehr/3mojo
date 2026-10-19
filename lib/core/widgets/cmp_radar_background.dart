import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '/core/theme/raen_colors.dart';

/// Sfondo decorativo "radar", solo effetto visivo: usato sia offline
/// (schermata Start, tema hero) che online (attesa in "Vicinanze", sotto il
/// velo ovale col testo).
///
/// Tre livelli, tutti nei colori del tema:
/// - una griglia di anelli fissi appena accennati e un fascio che ruota
///   lento (un giro ogni [_sweepPeriod]), sfumato verso il bordo;
/// - onde che partono dal centro a intervalli irregolari, rallentano
///   allontanandosi (easing non lineare) e si assottigliano mentre svaniscono,
///   ognuna con una scia morbida dietro il fronte;
/// - pochi cuoricini (rosso-cuore di `RaenColors`, dentro il disco bianco
///   quando il rosso sullo sfondo non si leggerebbe, come nell'icona) e
///   segnaposti (`primary`) che compaiono e spariscono con dissolvenze di
///   diversi secondi, lontani dal centro (dove c'è il contenuto) e tra loro;
///   quando uno sparisce ne nasce un altro altrove.
///
/// Un solo [Ticker] e nessun `setState` per frame: lo stato animato vive in
/// [_RadarScene], che fa ridisegnare solo il painter (dentro un
/// [RepaintBoundary]). Con le animazioni disattivate dal sistema
/// (`MediaQuery.disableAnimations`) resta un fotogramma fermo.
class CmpRadarBackground extends StatefulWidget {
  const CmpRadarBackground({super.key});

  @override
  State<CmpRadarBackground> createState() => _CmpRadarBackgroundState();
}

class _CmpRadarBackgroundState extends State<CmpRadarBackground>
    with SingleTickerProviderStateMixin {
  final _scene = _RadarScene(math.Random());
  late final Ticker _ticker = createTicker(_onTick);

  /// Tempo della scena all'avvio del ticker: `elapsed` riparte da zero a
  /// ogni `start()`, la scena no.
  double _timeBase = 0;
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;

    if (reduceMotion) {
      _ticker.stop();
      _scene.freeze();
    } else {
      _timeBase = _scene.time;
      _scene.populate(_timeBase);
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    _scene.advance(_timeBase + elapsed.inMicroseconds / 1e6);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final raen =
        theme.extension<RaenColors>() ??
        (colorScheme.brightness == Brightness.dark
            ? RaenColors.dark
            : RaenColors.light);
    // Sul blu pieno della home offline il rosso non si legge (2.1:1): lì il
    // cuore va nel disco bianco, come nell'icona.
    final heartReadsOnSurface =
        _contrastRatio(raen.heart, colorScheme.surface) >= 3;

    return RepaintBoundary(
      child: CustomPaint(
        painter: _RadarPainter(
          scene: _scene,
          ringColor: colorScheme.primary,
          pinColor: colorScheme.primary,
          heartColor: heartReadsOnSurface ? raen.heart : raen.onHeartDisc,
          heartDiscColor: heartReadsOnSurface ? null : raen.heartDisc,
        ),
      ),
    );
  }

  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }
}

// --- Tempi e quantità --------------------------------------------------------

/// Un giro completo del fascio, in secondi.
const double _sweepPeriod = 10;

/// Tempo che un'onda impiega dal centro al bordo, in secondi.
const double _wavePeriod = 6;

/// Sfasamento di ogni onda nel ciclo: volutamente non equidistanti.
const List<double> _waveOffsets = [0, 0.21, 0.5, 0.74];

/// Peso di ogni onda (spessore e intensità), alternato per variare il ritmo.
const List<double> _waveWeights = [1, 0.55, 0.85, 0.45];

/// Quanti cuoricini/segnaposti esistono contemporaneamente (non tutti sono
/// visibili nello stesso istante: alcuni stanno comparendo o svanendo).
const int _glyphCount = 6;

/// Durata di vita di un elemento: [_glyphMinLife] + fino a [_glyphLifeJitter].
const double _glyphMinLife = 8;
const double _glyphLifeJitter = 3;

/// Frazione della vita spesa in dissolvenza d'entrata e d'uscita: con 8–11 s
/// di vita sono 3–4.5 s per parte, con una breve pausa piena nel mezzo.
const double _glyphFade = 0.4;

/// Fascia (in unità normalizzate, 1 = bordo dell'area) in cui nascono gli
/// elementi: lontani dal centro, dentro l'area del radar.
const double _glyphMinRadius = 0.4;
const double _glyphMaxRadius = 0.92;

/// Distanza minima desiderata tra due elementi, in unità normalizzate.
const double _glyphSpacing = 0.45;

/// Fotogramma usato quando le animazioni sono disattivate.
const double _frozenTime = 2.4;

// --- Stato animato -----------------------------------------------------------

enum _GlyphKind { heart, pin }

@immutable
class _Glyph {
  const _Glyph({
    required this.kind,
    required this.unit,
    required this.bornAt,
    required this.lifetime,
    required this.size,
    required this.drift,
    required this.tilt,
  });

  final _GlyphKind kind;

  /// Posizione normalizzata rispetto al centro: (±1, ±1) = bordo dell'area.
  final Offset unit;

  /// Istante di nascita (secondi di scena); può essere nel futuro.
  final double bornAt;
  final double lifetime;

  /// Larghezza in pixel logici.
  final double size;

  /// Spostamento totale a fine vita, in pixel logici.
  final Offset drift;

  /// Inclinazione in radianti.
  final double tilt;

  _Glyph withBornAt(double value) => _Glyph(
    kind: kind,
    unit: unit,
    bornAt: value,
    lifetime: lifetime,
    size: size,
    drift: drift,
    tilt: tilt,
  );
}

/// Orologio della scena + elementi vivi. Avvisa il painter a ogni tick
/// (fa da `repaint` del [CustomPainter]), senza ricostruire widget.
class _RadarScene extends ChangeNotifier {
  _RadarScene(this._random);

  final math.Random _random;
  final List<_Glyph> glyphs = [];
  double time = 0;

  /// Riempie la scena con fasi già sparse, come se girasse da un po':
  /// alcuni elementi stanno comparendo, altri svanendo.
  void populate(double now) {
    time = now;
    glyphs.clear();
    for (var i = 0; i < _glyphCount; i++) {
      final glyph = _spawn(0);
      glyphs.add(glyph.withBornAt(now - glyph.lifetime * i / _glyphCount));
    }
    notifyListeners();
  }

  /// Fotogramma fermo: onde e fascio in una posa fissa, elementi al massimo.
  void freeze() {
    time = _frozenTime;
    glyphs.clear();
    for (var i = 0; i < _glyphCount - 1; i++) {
      final glyph = _spawn(0);
      glyphs.add(glyph.withBornAt(time - glyph.lifetime / 2));
    }
    notifyListeners();
  }

  void advance(double now) {
    // Ticker silenziato (pagina coperta) e poi ripreso: invece di far
    // rinascere tutti insieme gli elementi scaduti, riparte già "a regime".
    if (now - time > 1) {
      populate(now);
      return;
    }
    time = now;
    for (var i = 0; i < glyphs.length; i++) {
      final glyph = glyphs[i];
      if (now >= glyph.bornAt + glyph.lifetime) {
        // Il vecchio è ancora in lista mentre si sceglie il posto: il nuovo
        // nasce lontano anche da dove l'altro è appena sparito.
        glyphs[i] = _spawn(now + 0.6 + _random.nextDouble() * 1.8);
      }
    }
    notifyListeners();
  }

  _Glyph _spawn(double bornAt) {
    var best = Offset.zero;
    var bestDistance = -1.0;
    for (var attempt = 0; attempt < 16; attempt++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      // Radice: distribuzione uniforme sull'area della corona, non sul raggio.
      final radius = math.sqrt(
        lerpDouble(
          _glyphMinRadius * _glyphMinRadius,
          _glyphMaxRadius * _glyphMaxRadius,
          _random.nextDouble(),
        )!,
      );
      final candidate = Offset(math.cos(angle), math.sin(angle)) * radius;
      var nearest = double.infinity;
      for (final other in glyphs) {
        nearest = math.min(nearest, (other.unit - candidate).distance);
      }
      if (nearest > bestDistance) {
        bestDistance = nearest;
        best = candidate;
      }
      if (nearest >= _glyphSpacing) break;
    }

    final kind = _nextKind();
    final outward = best / best.distance;
    final isHeart = kind == _GlyphKind.heart;
    return _Glyph(
      kind: kind,
      unit: best,
      bornAt: bornAt,
      lifetime: _glyphMinLife + _random.nextDouble() * _glyphLifeJitter,
      size: (isHeart ? 13 : 15) + _random.nextDouble() * 6,
      // Cuori che salgono piano, segnaposti che si allontanano appena.
      drift: isHeart ? Offset(outward.dx * 4, -10) : outward * 6,
      tilt: (_random.nextDouble() - 0.5) * (isHeart ? 0.5 : 0.16),
    );
  }

  /// Tiene bilanciati cuori e segnaposti.
  _GlyphKind _nextKind() {
    final hearts = glyphs.where((g) => g.kind == _GlyphKind.heart).length;
    final pins = glyphs.length - hearts;
    if (hearts != pins) {
      return hearts < pins ? _GlyphKind.heart : _GlyphKind.pin;
    }
    return _random.nextBool() ? _GlyphKind.heart : _GlyphKind.pin;
  }
}

// --- Disegno -----------------------------------------------------------------

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.scene,
    required this.ringColor,
    required this.pinColor,
    required this.heartColor,
    required this.heartDiscColor,
  }) : super(repaint: scene);

  final _RadarScene scene;
  final Color ringColor;
  final Color pinColor;
  final Color heartColor;

  /// Se non nullo, il cuore va dentro un disco di questo colore.
  final Color? heartDiscColor;

  /// Cuore di larghezza 1, centrato sull'origine.
  static final Path _heartPath = Path()
    ..moveTo(0, 0.42)
    ..cubicTo(-0.12, 0.32, -0.5, 0.08, -0.5, -0.17)
    ..cubicTo(-0.5, -0.36, -0.36, -0.48, -0.22, -0.48)
    ..cubicTo(-0.11, -0.48, -0.03, -0.42, 0, -0.32)
    ..cubicTo(0.03, -0.42, 0.11, -0.48, 0.22, -0.48)
    ..cubicTo(0.36, -0.48, 0.5, -0.36, 0.5, -0.17)
    ..cubicTo(0.5, 0.08, 0.12, 0.32, 0, 0.42)
    ..close();

  /// Segnaposto a goccia di larghezza 1 col foro: testa centrata
  /// sull'origine, punta in basso.
  static final Path _pinPath = Path()
    ..fillType = PathFillType.evenOdd
    ..moveTo(0, 0.72)
    ..cubicTo(-0.14, 0.5, -0.5, 0.2, -0.5, -0.12)
    ..arcTo(
      Rect.fromCircle(center: const Offset(0, -0.12), radius: 0.5),
      math.pi,
      math.pi,
      false,
    )
    ..cubicTo(0.5, 0.2, 0.14, 0.5, 0, 0.72)
    ..close()
    ..addOval(Rect.fromCircle(center: const Offset(0, -0.12), radius: 0.19));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    final time = scene.time;

    _paintGrid(canvas, center, maxRadius);
    _paintSweep(canvas, center, maxRadius, time);
    _paintWaves(canvas, center, maxRadius, time);
    _paintGlyphs(canvas, size, center, maxRadius, time);
  }

  void _paintGrid(Canvas canvas, Offset center, double maxRadius) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ringColor.withValues(alpha: 0.08);
    for (final fraction in const [0.3, 0.6, 0.9]) {
      canvas.drawCircle(center, maxRadius * fraction, paint);
    }
  }

  void _paintSweep(Canvas canvas, Offset center, double maxRadius, double t) {
    final angle = (t / _sweepPeriod % 1) * 2 * math.pi;
    final rect = Rect.fromCircle(center: center, radius: maxRadius);
    final clear = ringColor.withValues(alpha: 0);

    canvas.saveLayer(rect, Paint());
    // Spicchio di ~70° che sfuma all'indietro rispetto al bordo d'attacco.
    canvas.drawCircle(
      center,
      maxRadius,
      Paint()
        ..shader = SweepGradient(
          colors: [clear, clear, ringColor.withValues(alpha: 0.11)],
          stops: const [0, 0.8, 1],
          transform: GradientRotation(angle),
        ).createShader(rect),
    );
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * maxRadius,
      Paint()
        ..strokeWidth = 1
        ..color = ringColor.withValues(alpha: 0.14),
    );
    // Maschera (solo alfa, il colore non conta): il fascio svanisce verso il
    // bordo invece di finire con un taglio netto.
    canvas.drawCircle(
      center,
      maxRadius,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = RadialGradient(
          colors: [ringColor, ringColor, clear],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
    canvas.restore();
  }

  void _paintWaves(Canvas canvas, Offset center, double maxRadius, double t) {
    final clear = ringColor.withValues(alpha: 0);
    for (var i = 0; i < _waveOffsets.length; i++) {
      final progress = (t / _wavePeriod + _waveOffsets[i]) % 1;
      // Parte veloce e rallenta verso il bordo.
      final eased = 1 - math.pow(1 - progress, 2.2).toDouble();
      final radius = maxRadius * eased;
      if (radius < 1) continue;

      final weight = _waveWeights[i];
      final fadeIn = (progress / 0.08).clamp(0.0, 1.0);
      final fade = fadeIn * math.pow(1 - progress, 1.3).toDouble();

      // Scia morbida appena dentro il fronte d'onda.
      final band = math.min(radius, maxRadius * 0.14);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              clear,
              clear,
              ringColor.withValues(alpha: 0.10 * fade * weight),
            ],
            stops: [0, 1 - band / radius, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lerpDouble(2.6, 0.7, progress)! * weight
          ..color = ringColor.withValues(alpha: (0.22 + 0.2 * weight) * fade),
      );
    }
  }

  void _paintGlyphs(
    Canvas canvas,
    Size size,
    Offset center,
    double maxRadius,
    double t,
  ) {
    // Area degli elementi: il cerchio del radar, allungato di poco sul lato
    // lungo per sfruttare anche lo spazio sopra e sotto il contenuto.
    final rx = math.min(size.width / 2, maxRadius * 1.3) * 0.9;
    final ry = math.min(size.height / 2, maxRadius * 1.3) * 0.9;

    for (final glyph in scene.glyphs) {
      final life = (t - glyph.bornAt) / glyph.lifetime;
      if (life <= 0 || life >= 1) continue;

      final double opacity;
      final double scale;
      if (life < _glyphFade) {
        final p = life / _glyphFade;
        opacity = Curves.easeInOut.transform(p);
        scale = lerpDouble(0.7, 1, Curves.easeOutCubic.transform(p))!;
      } else if (life > 1 - _glyphFade) {
        final p = (life - (1 - _glyphFade)) / _glyphFade;
        opacity = 1 - Curves.easeInOut.transform(p);
        scale = lerpDouble(1, 0.9, Curves.easeIn.transform(p))!;
      } else {
        opacity = 1;
        scale = 1;
      }
      if (opacity < 0.01) continue;

      final position =
          center +
          Offset(glyph.unit.dx * rx, glyph.unit.dy * ry) +
          glyph.drift * Curves.easeInOut.transform(life);
      final width = glyph.size * scale;

      canvas
        ..save()
        ..translate(position.dx, position.dy)
        ..rotate(glyph.tilt);
      switch (glyph.kind) {
        case _GlyphKind.heart:
          _paintHeart(canvas, width, opacity);
        case _GlyphKind.pin:
          _paintPin(canvas, width, opacity);
      }
      canvas.restore();
    }
  }

  void _paintHeart(Canvas canvas, double width, double opacity) {
    final discColor = heartDiscColor;
    if (discColor == null) {
      canvas
        ..scale(width)
        ..drawPath(
          _heartPath,
          Paint()..color = heartColor.withValues(alpha: 0.75 * opacity),
        );
      return;
    }
    // Disco e cuore sfumano insieme (un solo layer): il cuore resta pieno
    // dentro il layer, così sopra il blu si legge rosso e non viola; il
    // disco è velato, un alone più che un bollino.
    final discRadius = width * 0.62;
    canvas.saveLayer(
      Rect.fromCircle(center: Offset.zero, radius: discRadius + 1),
      Paint()..color = Color.fromRGBO(0, 0, 0, 0.9 * opacity),
    );
    canvas
      ..drawCircle(
        Offset.zero,
        discRadius,
        Paint()..color = discColor.withValues(alpha: 0.5),
      )
      ..translate(0, width * 0.03)
      ..scale(width * 0.62)
      ..drawPath(_heartPath, Paint()..color = heartColor)
      ..restore();
  }

  void _paintPin(Canvas canvas, double width, double opacity) {
    // Ombra a terra sotto la punta.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, width * 0.74),
        width: width * 0.55,
        height: width * 0.14,
      ),
      Paint()..color = pinColor.withValues(alpha: 0.22 * opacity),
    );
    canvas
      ..scale(width)
      ..drawPath(
        _pinPath,
        Paint()..color = pinColor.withValues(alpha: 0.6 * opacity),
      );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.pinColor != pinColor ||
      oldDelegate.heartColor != heartColor ||
      oldDelegate.heartDiscColor != heartDiscColor;
}
