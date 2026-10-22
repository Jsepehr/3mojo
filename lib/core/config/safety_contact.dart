/// Il contatto pubblicato per sicurezza e segnalazioni (Apple, guideline
/// 1.2: un'app con contenuti generati dagli utenti deve pubblicare un modo
/// per contattare chi la gestisce). È **l'unico** posto in cui è scritto:
/// lo mostra la pagina "Sicurezza e segnalazioni" (`UiSafety`).
///
/// **SEGNAPOSTO da sostituire prima della pubblicazione** con una casella
/// vera e presidiata: il dominio `.example` è riservato (RFC 2606) e non
/// riceve posta.
class SafetyContact {
  const SafetyContact._();

  static const email = 'safety@raen.example';
}
