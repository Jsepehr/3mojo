import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:threemojo_app/app.dart';

// Smoke test: l'app si avvia senza eccezioni e mostra la home offline
// (bottone Start) quando non c'è ancora nessuna sessione salvata.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home shows the Start button while offline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const App());
    // Avoid pumpAndSettle: the animated radar background never settles on
    // its own. Pump past ProEncounters' first refresh cycle (two chained
    // 300ms fake-network delays) so nothing is left in flight at teardown.
    await tester.pump(const Duration(milliseconds: 800));

    // The test environment defaults to the English locale.
    expect(find.text('Start'), findsOneWidget);
  });
}
