import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '/features/chat/presentation/providers/pro_chat.dart';
import '../pages/ui_active_match.dart';
import '../providers/pro_encounters.dart';

/// Osserva `ProEncounters.activeMatch` da qualsiasi punto dell'app e tiene
/// la pagina del match (`UiActiveMatch`) **allineata** a esso:
///
/// - appena c'è un match, la apre a schermo intero sopra qualunque pagina
///   (così "un solo incontro alla volta" si ottiene gratis dallo stack di
///   `Navigator`), con una vibrazione forte: è il momento più importante;
/// - quando il match non c'è più (finito dall'altra parte, sessione finita
///   o ripartita sul server) o diventa un altro, chiude la pagina che
///   aveva aperto — tiene il riferimento alla route proprio per questo —
///   insieme a ciò che la pagina aveva aperto sopra di sé (il dialogo di
///   conferma di fine match, se era aperto);
/// - quando la pagina si chiude, per qualsiasi motivo, chiude anche la
///   chat (`ProChat.close`): niente messaggi rimasti in memoria.
///
/// L'avviso "l'altra persona è uscita" lo mostra
/// `CmpEncounterNoticeListener`; la chat del match finito la cancella
/// `ProEncounters` (tramite gli use case).
class CmpMatchGate extends StatefulWidget {
  const CmpMatchGate({super.key, required this.child});

  final Widget child;

  @override
  State<CmpMatchGate> createState() => _CmpMatchGateState();
}

class _CmpMatchGateState extends State<CmpMatchGate> {
  Route<void>? _route;
  String? _routeRequestId;
  bool _syncScheduled = false;

  @override
  Widget build(BuildContext context) {
    final activeMatch = context.watch<ProEncounters>().activeMatch;
    if (activeMatch?.id != _routeRequestId && !_syncScheduled) {
      _syncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
    return widget.child;
  }

  void _sync() {
    _syncScheduled = false;
    if (!mounted) return;
    final match = context.read<ProEncounters>().activeMatch;
    if (match?.id == _routeRequestId) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final previous = _route;
    if (previous != null) {
      _route = null;
      _routeRequestId = null;
      if (previous.isActive) {
        // Prima ciò che la pagina del match ha aperto sopra di sé (es. il
        // dialogo "Terminare l'incontro?" mentre il partner lo chiude):
        // `removeRoute` toglierebbe la pagina ma lascerebbe il dialogo
        // orfano a schermo.
        if (!previous.isCurrent) {
          navigator.popUntil((route) => identical(route, previous));
        }
        navigator.removeRoute(previous);
      }
      context.read<ProChat>().close();
    }

    if (match == null) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => UiActiveMatch(request: match),
      fullscreenDialog: true,
    );
    _route = route;
    _routeRequestId = match.id;
    final proChat = context.read<ProChat>();
    HapticFeedback.heavyImpact();
    navigator.push(route).then((_) {
      // Chiusa dalla pagina stessa (l'utente ha terminato il match).
      if (!identical(_route, route)) return;
      _route = null;
      _routeRequestId = null;
      proChat.close();
    });
  }
}
