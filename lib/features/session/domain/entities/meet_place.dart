/// Il **luogo** (una fascia grossolana, mai il nome di un locale) in cui ci
/// si trova, scelto allo Start con un menu a tendina sotto il selfie.
///
/// **Lista chiusa** apposta: niente testo libero (da moderare, e che
/// collegherebbe le sessioni tra loro). Sul filo viaggia solo il nome del
/// valore (`bar`, `discoPub`, `cafe`, `club`, `event`, `outdoors`; [other] non si manda):
/// sono codici **stabili**, gli stessi di `PresenceProfile` nel server
/// (`server/lib/src/presence_profile.dart`) — non rinominarli senza cambiare
/// anche l'altro lato.
///
/// È pubblico come lo era l'intento: lo vedono le persone vicine in
/// "Vicinanze" e nelle richieste, **tranne** [other] (non è una
/// dichiarazione: non si mostra nulla). Vale solo per la sessione, solo in
/// memoria, e si azzera a End: non è nel profilo. Adatta anche le proposte
/// di chi manda una richiesta (`ProposalsForPlaceUseCase`).
enum MeetPlace {
  bar,
  discoPub,
  cafe,
  club,
  event,
  outdoors,
  other;

  /// Il valore di partenza e di ripiego: "Altro / preferisco non dirlo".
  static const fallback = MeetPlace.other;

  /// Il luogo è una dichiarazione da mostrare agli altri? `other` no.
  bool get isDeclared => this != MeetPlace.other;
}
