import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/app.dart';

void main() {
  testWidgets('App boots and shows both navigation destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const App());
    // Avoid pumpAndSettle: while loading, both pages show an indeterminate
    // CircularProgressIndicator, whose animation never settles on its own.
    await tester.pump(const Duration(milliseconds: 500));

    // The test environment defaults to the English locale.
    expect(find.text('Nearby'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
  });
}
