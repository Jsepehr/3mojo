import 'package:flutter/material.dart';

/// Indicatore di caricamento animato — tre puntini che rimbalzano in
/// sequenza — sostituto 1 a 1 dello spoglio `CircularProgressIndicator`
/// per le attese dell'app (persone vicine, cronologia chat, verifica del
/// selfie), sia a piena pagina che inline dentro un bottone.
class CmpLoadingIndicator extends StatefulWidget {
  const CmpLoadingIndicator({super.key, this.size = 48, this.color});

  final double size;
  final Color? color;

  @override
  State<CmpLoadingIndicator> createState() => _CmpLoadingIndicatorState();
}

class _CmpLoadingIndicatorState extends State<CmpLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  static const int _dotCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final dotSize = widget.size / 4;

    return SizedBox(
      width: widget.size,
      height: dotSize,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_dotCount, (i) {
              final delay = i / _dotCount;
              final t = (_controller.value - delay) % 1.0;
              final bounce = (1 - (t * 2 - 1).abs()).clamp(0.0, 1.0);
              return Transform.scale(
                scale: 0.5 + bounce * 0.5,
                child: Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
