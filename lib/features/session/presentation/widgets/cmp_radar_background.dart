import 'package:flutter/material.dart';

class CmpRadarBackground extends StatefulWidget {
  const CmpRadarBackground({super.key});

  @override
  State<CmpRadarBackground> createState() => _CmpRadarBackgroundState();
}

class _CmpRadarBackgroundState extends State<CmpRadarBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _RadarPainter(progress: _controller.value, color: color),
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const int _ringCount = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide / 2;

    for (var i = 0; i < _ringCount; i++) {
      final ringProgress = (progress + i / _ringCount) % 1;
      final opacity = (1 - ringProgress).clamp(0.0, 1.0);

      canvas.drawCircle(
        center,
        maxRadius * ringProgress,
        Paint()
          ..color = color.withValues(alpha: opacity * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
