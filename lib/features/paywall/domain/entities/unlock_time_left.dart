import 'package:equatable/equatable.dart';

/// Quanto resta di uno sblocco attivo, già ridotto a ciò che si mostra
/// (`GetUnlockTimeLeftUseCase`): minuti interi, mai secondi — niente conto
/// alla rovescia.
///
/// Due valori sono uguali se si mostrano uguali ([wholeMinutes],
/// [isEndingSoon]); [nextChangeIn] è solo il promemoria per il timer.
class UnlockTimeLeft extends Equatable {
  const UnlockTimeLeft({
    required this.wholeMinutes,
    required this.isEndingSoon,
    required this.nextChangeIn,
  });

  /// I minuti interi che restano **oltre** quello in corso: con 1 h 42 min e
  /// 30 s restanti è 102 ("1 h 42 min"); `0` nell'ultimo minuto ("meno di
  /// un minuto").
  final int wholeMinutes;

  int get hours => wholeMinutes ~/ 60;

  int get minutes => wholeMinutes % 60;

  /// Negli ultimi 10 minuti: la UI lo segnala con sobrietà, nient'altro.
  final bool isEndingSoon;

  /// Fra quanto [wholeMinutes] scende di uno (o, nell'ultimo minuto, lo
  /// sblocco scade): è il confine del minuto su cui riallineare il timer.
  final Duration nextChangeIn;

  @override
  List<Object?> get props => [wholeMinutes, isEndingSoon];
}
