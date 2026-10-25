import 'package:flutter/widgets.dart';

/// Segna il sottoalbero della **demo dichiarata** (`DemoScope`, in
/// `lib/demo_scope.dart`): chi sta sotto sa di mostrare persone
/// dimostrative e lo dice (badge "Demo" sulle tile, sulle richieste e nella
/// chat, nota "in demo non viene inviato nulla" su Blocca/Segnala, niente
/// drawer). Non cambia nessuna regola: le regole restano negli use case, e
/// ciò che la demo fa davvero lo decidono i datasource finti che `DemoScope`
/// mette al posto di quelli reali.
///
/// Fuori dalla demo non c'è: [isActive] è `false`.
class DemoMode extends InheritedWidget {
  const DemoMode({super.key, required super.child});

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoMode>() != null;

  @override
  bool updateShouldNotify(DemoMode oldWidget) => false;
}
