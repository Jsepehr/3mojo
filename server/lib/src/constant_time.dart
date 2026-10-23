/// Confronto di due segreti che non si ferma al primo carattere diverso: il
/// tempo di risposta non rivela quanta parte del token è giusta. Usato dagli
/// endpoint protetti da token (`/debug/sessions`, `/admin/reports`,
/// `/paywall/notifications/google`) e dalle ricevute del negozio simulato.
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
