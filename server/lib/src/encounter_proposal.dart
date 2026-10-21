/// Cosa propone chi manda una richiesta d'incontro ("vuole salutarti",
/// "vuole bere qualcosa insieme a te"…) — **lista chiusa** di codici, gli
/// stessi di `EncounterProposal` nel client
/// (`lib/features/encounters/domain/entities/encounter_proposal.dart`): se
/// cambia una, va cambiata anche l'altra. Niente testo libero (da moderare,
/// e che collegherebbe le sessioni tra loro), niente opzioni romantiche.
///
/// Sul filo viaggia solo il codice: la frase la traduce il client di chi la
/// riceve, nella sua lingua.
abstract final class EncounterProposal {
  static const sayHi = 'sayHi';
  static const chat = 'chat';
  static const friendship = 'friendship';
  static const getToKnow = 'getToKnow';
  static const drink = 'drink';

  static const values = {sayHi, chat, friendship, getToKnow, drink};

  /// La proposta di chi non ne manda una (client più vecchi) o ne manda
  /// una sconosciuta: la frase neutra di sempre, "vuole conoscerti".
  static const fallback = getToKnow;

  /// Il codice se è nella lista chiusa, altrimenti [fallback] — mai un
  /// valore arbitrario nei payload verso l'altra persona.
  static String parse(Object? raw) =>
      raw is String && values.contains(raw) ? raw : fallback;
}
