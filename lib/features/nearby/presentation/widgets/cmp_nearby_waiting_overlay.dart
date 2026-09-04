import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '/features/session/presentation/widgets/cmp_radar_background.dart';
import '/l10n/generated/app_localizations.dart';

/// Copre l'intera area di "Vicinanze" nei due momenti in cui non c'è ancora
/// una lista da mostrare: connessione al server appena andati online, e
/// lista vuota una volta connessi. Stesso radar animato della schermata
/// Start come sfondo (stesso linguaggio visivo di "sto cercando persone
/// intorno a te"), con una card colorata che vi galleggia sopra — [title]
/// distingue i due casi. Dentro, un testo cambia a rotazione con un
/// dissolvenza incrociata (non uno scorrimento, per non suggerire "altre
/// pagine da sfogliare"), in ordine casuale (mai la stessa due volte di
/// fila) così anche a rivederla più volte non diventa prevedibile,
/// spiegando le vere regole del server (raggio,
/// permanenza minima, probabilità d'incontro, niente profili permanenti, un
/// incontro alla volta) così l'attesa si legge come comportamento
/// intenzionale, non come un bug.
class CmpNearbyWaitingOverlay extends StatefulWidget {
  const CmpNearbyWaitingOverlay({super.key, required this.title});

  final String title;

  @override
  State<CmpNearbyWaitingOverlay> createState() =>
      _CmpNearbyWaitingOverlayState();
}

class _CmpNearbyWaitingOverlayState extends State<CmpNearbyWaitingOverlay> {
  static const _tipInterval = Duration(seconds: 6);
  static const _tipCount = 4;

  final _random = Random();
  late final Timer _timer;
  int _tipIndex = 0;

  @override
  void initState() {
    super.initState();
    _tipIndex = _random.nextInt(_tipCount);
    _timer = Timer.periodic(_tipInterval, (_) => setState(_pickNextTip));
  }

  void _pickNextTip() {
    if (_tipCount < 2) return;
    var next = _random.nextInt(_tipCount);
    while (next == _tipIndex) {
      next = _random.nextInt(_tipCount);
    }
    _tipIndex = next;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final tips = [
      l10n.nearbyEmptyTipRadius,
      l10n.nearbyEmptyTipMeetingChance,
      l10n.nearbyEmptyTipEphemeral,
      l10n.nearbyEmptyTipOneAtATime,
    ];

    return Stack(
      children: [
        const Positioned.fill(child: CmpRadarBackground()),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colorScheme.primary, colorScheme.tertiary],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 84,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 600),
                    child: Center(
                      key: ValueKey(_tipIndex),
                      child: Text(
                        tips[_tipIndex],
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
