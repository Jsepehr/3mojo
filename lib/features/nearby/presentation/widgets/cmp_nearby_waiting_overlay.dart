import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '/core/widgets/cmp_radar_background.dart';
import '/l10n/generated/app_localizations.dart';

/// Copre l'intera area di "Vicinanze" nei due momenti in cui non c'è ancora
/// una lista da mostrare: connessione al server appena andati online, e
/// lista vuota una volta connessi. Stesso radar animato della schermata
/// Start come sfondo (stesso linguaggio visivo di "sto cercando persone
/// intorno a te"), con un velo ovale e sfumato che vi galleggia sopra —
/// [title] distingue i due casi. Dentro, un testo cambia a
/// rotazione con un dissolvenza incrociata (non uno scorrimento, per non
/// suggerire "altre pagine da sfogliare"), in ordine casuale (mai la stessa
/// due volte di fila) così anche a rivederla più volte non diventa
/// prevedibile, spiegando le vere regole del server (raggio,
/// permanenza minima, probabilità d'incontro, niente profili permanenti, un
/// incontro alla volta) così l'attesa si legge come comportamento
/// intenzionale, non come un bug.
class CmpNearbyWaitingOverlay extends StatefulWidget {
  const CmpNearbyWaitingOverlay({super.key, required this.title});

  final String title;

  @override
  State<CmpNearbyWaitingOverlay> createState() =>
      _CmpNearbyWaitingOverlayState();
}

class _CmpNearbyWaitingOverlayState extends State<CmpNearbyWaitingOverlay> {
  static const _tipInterval = Duration(seconds: 6);
  static const _tipCount = 4;

  /// Il velo dietro il testo sborda oltre il testo: di lato metà del
  /// margine, sopra e sotto di più, così la forma è un ovale alto come un
  /// uovo e non una striscia — ma abbastanza stretto da lasciare scoperto
  /// il radar tutto intorno.
  static const _glowBleedX = 16.0;
  static const _glowBleedY = 48.0;

  /// Opacità del velo al centro. Il velo ha il colore della superficie
  /// (appena tinto di blu), non il blu pieno: serve solo a calmare il radar
  /// dietro al testo, così l'animazione resta colorata e visibile anche
  /// sotto, attenuata. Con testo scuro/chiaro del tema il contrasto resta
  /// ≥ 4.5:1 anche quando un cuore o un segnaposto passa dietro una riga.
  static const _glowPeakOpacity = 0.85;

  /// Alone tipografico (stesso colore del velo) attorno alle lettere:
  /// stacca il testo da anelli, onde e segnaposti che ci passano sotto.
  static const _textHaloBlurRadii = [3.0, 8.0];

  final _random = Random();
  late final Timer _timer;
  int _tipIndex = 0;

  @override
  void initState() {
    super.initState();
    _tipIndex = _random.nextInt(_tipCount);
    _timer = Timer.periodic(_tipInterval, (_) => setState(_pickNextTip));
  }

  void _pickNextTip() {
    if (_tipCount < 2) return;
    var next = _random.nextInt(_tipCount);
    while (next == _tipIndex) {
      next = _random.nextInt(_tipCount);
    }
    _tipIndex = next;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final veilColor = colorScheme.surfaceContainerHigh;
    final textHalo = [
      for (final blurRadius in _textHaloBlurRadii)
        Shadow(color: veilColor, blurRadius: blurRadius),
    ];
    final tips = [
      l10n.we_only_show_people_who_stay_put_within_100_meters,
      l10n.the_longer_someone_stays_in_one_place,
      l10n.no_names_no_public_profile,
      l10n.accept_one_request_and_the_others_cancel_automatically,
    ];

    return Stack(
      children: [
        const Positioned.fill(child: CmpRadarBackground()),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Niente card dai bordi netti: un velo ovale che parte
                // quasi pieno al centro e svanisce verso i lati, così il
                // testo resta leggibile e il radar si vede tutto intorno.
                Positioned(
                  left: -_glowBleedX,
                  right: -_glowBleedX,
                  top: -_glowBleedY,
                  bottom: -_glowBleedY,
                  child: CustomPaint(
                    painter: _OvalGlowPainter(
                      color: veilColor,
                      peakOpacity: _glowPeakOpacity,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          shadows: textHalo,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 84,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 600),
                          child: Center(
                            key: ValueKey(_tipIndex),
                            child: Text(
                              tips[_tipIndex],
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface,
                                shadows: textHalo,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Disegna un ovale che riempie tutta l'area, con una sfumatura radiale
/// (schiacciata sull'ovale, non un cerchio) di un solo [color], che parte da
/// [peakOpacity] al centro e arriva a 0% sul contorno. La discesa è morbida:
/// lenta vicino al centro, dove c'è il testo, più rapida verso il bordo.
class _OvalGlowPainter extends CustomPainter {
  _OvalGlowPainter({required this.color, required this.peakOpacity});

  final Color color;
  final double peakOpacity;

  /// Opacità relativa (× [peakOpacity]) a ogni tappa della sfumatura.
  static const _falloff = [1.0, 0.92, 0.65, 0.26, 0.0];
  static const _stops = [0.0, 0.45, 0.72, 0.88, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final unitCircle = Rect.fromCircle(center: Offset.zero, radius: 1);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          for (final f in _falloff) color.withValues(alpha: peakOpacity * f),
        ],
        stops: _stops,
      ).createShader(unitCircle);

    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(size.width / 2, size.height / 2)
      ..drawOval(unitCircle, paint)
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _OvalGlowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.peakOpacity != peakOpacity;
}
