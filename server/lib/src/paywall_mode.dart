/// Come il server tratta il paywall delle foto (`PAYWALL_MODE`).
enum PaywallMode {
  /// Il paywall di sempre: un terzo delle persone più lontane è gratis, le
  /// altre arrivano `locked` e senza foto finché non c'è uno sblocco valido.
  /// È il default, anche con un valore sbagliato.
  paid,

  /// Tutto gratis: nessuna persona arriva `locked`, chiunque vede ogni foto.
  /// Per i primi mesi (lancio), senza toccare le app: il blocco lo decide
  /// solo il server. Gli acquisti non cambiano (restano com'erano: chi ha
  /// già uno sblocco continua ad averlo) e per tornare a pagamento basta
  /// togliere la variabile e riavviare.
  free,
}

/// `PAYWALL_MODE` letto dall'ambiente, con l'eventuale avviso da scrivere
/// nel log all'avvio.
class PaywallConfig {
  const PaywallConfig({required this.mode, this.problem});

  /// `PAYWALL_MODE` manca o è `paid` → [PaywallMode.paid]; `free` →
  /// [PaywallMode.free]; qualsiasi altro valore → [PaywallMode.paid] con un
  /// [problem]: un refuso non deve mai regalare le foto a tutti in silenzio.
  factory PaywallConfig.fromEnvironment(Map<String, String> env) {
    final raw = (env[variable] ?? '').trim().toLowerCase();
    return switch (raw) {
      '' || 'paid' => const PaywallConfig(mode: PaywallMode.paid),
      'free' => const PaywallConfig(mode: PaywallMode.free),
      _ => PaywallConfig(
        mode: PaywallMode.paid,
        problem:
            '$variable="${env[variable]!.trim()}" non valido (paid|free): '
            'resta il paywall a pagamento.',
      ),
    };
  }

  static const variable = 'PAYWALL_MODE';

  final PaywallMode mode;
  final String? problem;
}
