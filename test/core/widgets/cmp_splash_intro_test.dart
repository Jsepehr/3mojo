import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/widgets/cmp_splash_intro.dart';

Widget _host({required VoidCallback onFinished, bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: CmpSplashIntro(onFinished: onFinished),
    ),
  );
}

/// L'angolo della rotazione attorno all'asse verticale, letto dalla matrice
/// del `Transform` dell'icona (M[0][0] = cos θ).
double _cosOfTurn(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(CmpSplashIntro),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.entry(0, 0);
}

void main() {
  const total = Duration(
    milliseconds: 250 + 900 + 250 + 300,
  ); // hold+giro+hold+fade

  testWidgets('the icon makes one full turn around the vertical axis, then '
      'reports it is finished', (tester) async {
    var finished = 0;
    await tester.pumpWidget(_host(onFinished: () => finished++));

    // Fermo e intero prima del giro.
    expect(_cosOfTurn(tester), closeTo(1, 1e-6));

    // A metà del giro è di spalle (cos θ ≈ -1)…
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 450));
    expect(_cosOfTurn(tester), lessThan(-0.9));

    // …e dopo il giro intero è di nuovo di fronte.
    await tester.pump(const Duration(milliseconds: 450));
    expect(_cosOfTurn(tester), closeTo(1, 1e-6));

    expect(finished, 0);
    // Due passi: il primo fotogramma chiude l'animazione, poi partono la
    // pausa finale e la dissolvenza.
    await tester.pump(total);
    await tester.pump(total);
    expect(finished, 1);
  });

  testWidgets('with reduced motion the icon does not rotate', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      _host(onFinished: () => finished++, reduceMotion: true),
    );

    await tester.pump(const Duration(milliseconds: 250));
    expect(_cosOfTurn(tester), closeTo(1, 1e-6));

    await tester.pump(CmpSplashIntro.fadeDuration * 2);
    expect(finished, 1);
  });

  testWidgets('does not block touches nor speak to the screen reader', (
    tester,
  ) async {
    await tester.pumpWidget(_host(onFinished: () {}));

    expect(
      find.descendant(
        of: find.byType(CmpSplashIntro),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(CmpSplashIntro),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    await tester.pump(total * 2);
  });
}
