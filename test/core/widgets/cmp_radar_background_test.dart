import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threemojo_app/core/widgets/cmp_radar_background.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: SizedBox(width: 360, height: 640, child: child));

void main() {
  testWidgets('with emojis the animation runs for a long time without '
      'errors', (tester) async {
    await tester.pumpWidget(
      _wrap(const CmpRadarBackground(emojis: ['☕', '🤝', '🙂', '🥤', '💃'])),
    );

    // Abbastanza da far nascere, svanire e rinascere tutti gli elementi.
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the emojis while it runs is fine, and so is an empty '
      'list', (tester) async {
    await tester.pumpWidget(
      _wrap(const CmpRadarBackground(emojis: ['☕', '💃'])),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(_wrap(const CmpRadarBackground()));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('with animations disabled it draws one still frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _wrap(const CmpRadarBackground(emojis: ['☕', '💃'])),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
  });
}
