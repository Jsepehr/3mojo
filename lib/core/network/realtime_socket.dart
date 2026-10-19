/// Un socket WebSocket ridotto all'essenziale che serve a
/// `RealtimeConnection` — un'astrazione sottile sopra `WebSocketChannel`, così
/// la connessione si può provare nei test con un socket finto e la scelta
/// della piattaforma (ping nativo su mobile/desktop, no su web) resta fuori
/// dalla logica di riconnessione.
abstract class RealtimeSocket {
  /// Frame in arrivo dal server (stringhe JSON). Emette un errore e si
  /// chiude se la connessione non riesce o cade.
  Stream<dynamic> get stream;

  /// Completa quando la connessione è stabilita; fallisce se non riesce
  /// (l'errore vero arriva comunque anche su [stream]).
  Future<void> get ready;

  /// Codice di chiusura mandato dal server, dopo la chiusura (es. 4008 =
  /// troppi Start dallo stesso IP), o `null`.
  int? get closeCode;

  void add(String data);

  Future<void> close([int? closeCode]);
}

/// Crea un [RealtimeSocket] verso [uri] — iniettabile in `RealtimeConnection`
/// per i test.
typedef RealtimeSocketFactory = RealtimeSocket Function(Uri uri);
