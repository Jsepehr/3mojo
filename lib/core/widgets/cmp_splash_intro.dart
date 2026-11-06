import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Introduzione all'avvio: l'icona dell'app (il segnaposto col cuore rosso)
/// compare sul blu di marca e fa **un giro completo attorno all'asse
/// verticale**, poi si dissolve e lascia vedere la home, che intanto si è
/// già costruita sotto.
///
/// Continua lo splash nativo — stesso blu, in chiaro e scuro, niente lampo
/// di altro colore — che su iOS e su Android prima della 12 non può animarsi.
/// L'icona è una tessera bianca dagli angoli arrotondati, perché il
/// segnaposto è blu e sullo stesso blu non si vedrebbe.
///
/// Con "riduci movimento" attivo ([MediaQueryData.disableAnimations]) niente
/// rotazione: l'icona compare ferma e si dissolve. Non intercetta i tocchi e
/// non è letta dallo screen reader (è decorazione).
class CmpSplashIntro extends StatefulWidget {
  const CmpSplashIntro({super.key, required this.onFinished});

  /// Chiamata una volta, quando la dissolvenza è finita e il widget può
  /// essere tolto.
  final VoidCallback onFinished;

  /// Il blu dello splash nativo (`launch_background_color` su Android,
  /// `LaunchScreen.storyboard` su iOS): deve restare uguale.
  static const background = Color(0xFF0236B3);

  static const iconAsset = 'assets/branding/splash_icon.png';

  /// Un giro, con partenza e arrivo dolci.
  static const spinDuration = Duration(milliseconds: 900);

  /// L'icona resta ferma e intera prima e dopo il giro.
  static const holdDuration = Duration(milliseconds: 250);

  static const fadeDuration = Duration(milliseconds: 300);

  @override
  State<CmpSplashIntro> createState() => _CmpSplashIntroState();
}

class _CmpSplashIntroState extends State<CmpSplashIntro>
    with SingleTickerProviderStateMixin {
  static const _iconSize = 120.0;

  // Profondità della prospettiva: abbastanza per leggere il giro come 3D,
  // non tanto da deformare l'icona a 45°.
  static const _perspective = 0.0012;

  late final AnimationController _controller;
  bool _started = false;
  bool _fading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _run(reduceMotion: MediaQuery.disableAnimationsOf(context));
  }

  Future<void> _run({required bool reduceMotion}) async {
    // Mentre l'icona è ferma e intera si può solo aspettare: l'animazione
    // è tutta in `_controller` (0 → 1 = il giro).
    await Future<void>.delayed(CmpSplashIntro.holdDuration);
    if (!mounted) return;
    if (!reduceMotion) {
      await _controller.animateTo(
        1,
        duration: CmpSplashIntro.spinDuration,
        curve: Curves.easeInOutCubic,
      );
      if (!mounted) return;
      await Future<void>.delayed(CmpSplashIntro.holdDuration);
      if (!mounted) return;
    }
    setState(() => _fading = true);
    await Future<void>.delayed(CmpSplashIntro.fadeDuration);
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _fading ? 0 : 1,
          duration: CmpSplashIntro.fadeDuration,
          child: ColoredBox(
            color: CmpSplashIntro.background,
            child: Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, _perspective)
                    ..rotateY(_controller.value * 2 * math.pi),
                  child: child,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_iconSize * 0.225),
                  child: Image.asset(
                    CmpSplashIntro.iconAsset,
                    width: _iconSize,
                    height: _iconSize,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
