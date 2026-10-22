/// Perché si segnala una persona: una **lista chiusa**, niente testo libero
/// (da moderare, e che potrebbe contenere dati di chiunque). Sul filo va il
/// nome del valore, lo stesso dell'enum `ReportReason` del server, che lo
/// valida (fuori lista → `rejected` `invalidReason`).
enum ReportReason {
  /// La foto è falsa o di un'altra persona.
  fakePhoto,

  /// La foto è inappropriata (sessuale, violenta, offensiva).
  inappropriatePhoto,

  /// Molestie o messaggi offensivi.
  harassment,

  /// Sembra minorenne.
  underage,

  /// Spam o truffa.
  spam,

  /// Altro.
  other,
}
