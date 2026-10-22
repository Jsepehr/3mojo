/// Perché una persona viene segnalata — **lista chiusa**, stessi codici
/// dell'app (`ReportReason` in `lib/features/safety/domain/entities/`).
/// Niente testo libero: non va moderato a sua volta, non porta dati
/// personali di chi segnala e non si può usare per scrivere qualcosa
/// all'altra persona.
enum ReportReason {
  /// Foto falsa o di un'altra persona.
  fakePhoto,

  /// Foto inappropriata.
  inappropriatePhoto,

  /// Molestie o messaggi offensivi.
  harassment,

  /// Sembra minorenne.
  underage,

  /// Spam o truffa.
  spam,

  /// Altro.
  other;

  /// Il motivo con codice [raw], o `null` se manca o non è nella lista: a
  /// differenza delle proposte d'incontro non c'è un ripiego, una
  /// segnalazione con un motivo inventato si rifiuta (`invalidReason`).
  static ReportReason? parse(Object? raw) {
    for (final reason in values) {
      if (reason.name == raw) return reason;
    }
    return null;
  }
}
