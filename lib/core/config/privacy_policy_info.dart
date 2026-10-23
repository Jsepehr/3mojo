/// L'unico posto con i dati dell'**informativa privacy** che dipendono dal
/// titolare: chi è, come lo si contatta, dove è pubblicata. Li mostra la
/// pagina `UiPrivacyPolicy`; [publicUrl] va anche nelle schede degli store
/// (App Store Connect → Privacy Policy URL, Play Console → Contenuti
/// dell'app → Norme sulla privacy). Il contatto di sicurezza resta in
/// `SafetyContact`.
///
/// **SEGNAPOSTO da compilare prima della pubblicazione** (come nella bozza
/// `docs/privacy/informativa_bozza.md`): tutti i valori tra parentesi
/// quadre e l'URL `.example`, che è un dominio riservato (RFC 2606) e non
/// esiste. Il testo dell'informativa è negli ARB (`privacy_*`): se cambia
/// nella sostanza si alzano [version] e [lastUpdated], e lo si dice
/// nell'app (sezione "Modifiche").
class PrivacyPolicyInfo {
  const PrivacyPolicyInfo._();

  /// Versione del testo dell'informativa mostrato nell'app.
  static const version = 1;

  /// Data dell'ultimo aggiornamento del testo (mese da 1 a 12).
  /// TODO(privacy): la data di pubblicazione dell'informativa definitiva.
  static const lastUpdatedYear = 2026;
  static const lastUpdatedMonth = 10;
  static const lastUpdatedDay = 23;

  static DateTime get lastUpdated =>
      DateTime(lastUpdatedYear, lastUpdatedMonth, lastUpdatedDay);

  /// Titolare del trattamento: ragione sociale, sede, P.IVA.
  /// TODO(privacy): compilare.
  static const controller =
      '[Titolare da compilare: ragione sociale, sede, P.IVA]';

  /// Casella per le richieste privacy (diritti, consenso, reclami).
  /// TODO(privacy): una casella vera e presidiata.
  static const privacyEmail = '[privacy@… da compilare]';

  /// Contatto del Responsabile della protezione dei dati, se nominato
  /// (`null` = non nominato: la riga non si mostra).
  /// TODO(privacy): decidere (DPIA §8, punto 1).
  static const String? dpoContact = null;

  /// Il fornitore di hosting dei server e il Paese (responsabile art. 28).
  /// TODO(privacy): compilare.
  static const hostingProvider =
      '[Fornitore di hosting, Paese UE: da compilare]';

  /// Per quanto il fornitore di hosting tiene i log tecnici (IP e orari).
  /// TODO(privacy): compilare (raccomandazione DPIA: ≤ 7 giorni).
  static const hostingLogRetention = '[… giorni: da compilare]';

  /// Le garanzie per i trasferimenti verso gli Stati Uniti (Apple, Google).
  /// TODO(privacy): verificare con il consulente.
  static const transferSafeguards =
      '[Data Privacy Framework UE-USA / clausole contrattuali tipo: da '
      'verificare]';

  /// Indirizzo web stabile dell'informativa pubblicata (richiesto dagli
  /// store). TODO(privacy): l'URL vero.
  static const publicUrl = 'https://raen.example/privacy';
}
