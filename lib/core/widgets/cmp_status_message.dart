import 'package:flutter/material.dart';

import 'cmp_loading_indicator.dart';

/// Colore dell'avviso: [neutral] per gli stati che non sono "colpa" di
/// nessuno e si risolvono da soli o con un gesto dell'utente (offline, GPS
/// spento, permesso da concedere) — nel blu del brand; [error] per un
/// errore vero e inatteso — nei colori di errore del tema.
enum CmpStatusMessageTone { neutral, error }

/// Un bottone di [CmpStatusMessage]. Con [isBusy] mostra i puntini di
/// caricamento al posto dell'icona e ignora i tap (senza diventare grigio:
/// è un "ci sto lavorando", non un "non si può").
class CmpStatusMessageAction {
  const CmpStatusMessageAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isBusy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isBusy;
}

/// Avviso a tutta area al posto di un contenuto che ora non si può
/// mostrare (offline, posizione spenta, errore...): icona grande dentro un
/// disco morbido colorato dal tema, titolo breve, una riga di spiegazione
/// e fino a due azioni. Al posto della spoglia `Text` centrata.
///
/// Entra con una dissolvenza e un leggero ingrandimento; con [pulse] (per
/// gli stati in cui l'app sta già riprovando da sola) dal disco partono
/// onde lente che si allargano e svaniscono. Con le animazioni ridotte di
/// sistema (`MediaQuery.disableAnimations`) è un fotogramma fermo.
///
/// Generico, in `core/`: non sa nulla di `Failure` né di feature — chi lo
/// usa sceglie icona e testi (vedi `CmpNearbyErrorState`).
class CmpStatusMessage extends StatefulWidget {
  const CmpStatusMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.tone = CmpStatusMessageTone.neutral,
    this.pulse = false,
    this.primaryAction,
    this.secondaryAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final CmpStatusMessageTone tone;
  final bool pulse;
  final CmpStatusMessageAction? primaryAction;
  final CmpStatusMessageAction? secondaryAction;

  @override
  State<CmpStatusMessage> createState() => _CmpStatusMessageState();
}

class _CmpStatusMessageState extends State<CmpStatusMessage>
    with TickerProviderStateMixin {
  static const double _discSize = 104;
  static const double _iconSize = 48;

  /// Quanto si allarga un'onda prima di sparire, rispetto al disco.
  static const double _waveMaxScale = 1.6;
  static const int _waveCount = 2;

  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  late final Animation<double> _contentOpacity = CurvedAnimation(
    parent: _entry,
    curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
  );
  late final Animation<Offset> _contentOffset = Tween(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic));
  late final Animation<double> _discScale = Tween(begin: 0.6, end: 1.0).animate(
    CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.1, 1.0, curve: Curves.easeOutBack),
    ),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _entry.value = 1;
    } else if (!_entry.isCompleted && !_entry.isAnimating) {
      _entry.forward();
    }
    _syncWave();
  }

  @override
  void didUpdateWidget(CmpStatusMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulse != widget.pulse) _syncWave();
  }

  void _syncWave() {
    if (widget.pulse && !_reduceMotion) {
      if (!_wave.isAnimating) _wave.repeat();
    } else {
      _wave
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (container, onContainer) = switch (widget.tone) {
      CmpStatusMessageTone.neutral => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      CmpStatusMessageTone.error => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
    };

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _discScale,
          child: _buildBadge(container, onContainer),
        ),
        const SizedBox(height: 28),
        Semantics(
          header: true,
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        if (widget.primaryAction != null) ...[
          const SizedBox(height: 28),
          _buildPrimaryButton(widget.primaryAction!, colorScheme),
        ],
        if (widget.secondaryAction != null) ...[
          const SizedBox(height: 4),
          _buildSecondaryButton(widget.secondaryAction!),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: FadeTransition(
                    opacity: _contentOpacity,
                    child: SlideTransition(
                      position: _contentOffset,
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Disco con l'icona, e dietro le onde (solo con [CmpStatusMessage.pulse]).
  /// L'area è già quella dell'onda più larga, così il layout non si muove.
  Widget _buildBadge(Color container, Color onContainer) {
    const areaSize = _discSize * _waveMaxScale;

    return SizedBox.square(
      dimension: areaSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.pulse)
            for (var i = 0; i < _waveCount; i++)
              AnimatedBuilder(
                animation: _wave,
                builder: (context, child) {
                  if (_reduceMotion) return const SizedBox.shrink();
                  final t = (_wave.value + i / _waveCount) % 1.0;
                  final eased = Curves.easeOut.transform(t);
                  return Opacity(
                    opacity: (1 - t) * 0.55,
                    child: Transform.scale(
                      scale: 1 + (_waveMaxScale - 1) * eased,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: _discSize,
                  height: _discSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: container,
                  ),
                ),
              ),
          // Alone fisso e tenue attorno al disco: dà profondità anche
          // quando le onde sono ferme.
          Container(
            width: _discSize + 20,
            height: _discSize + 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: container.withValues(alpha: 0.45),
            ),
          ),
          Container(
            width: _discSize,
            height: _discSize,
            decoration: BoxDecoration(shape: BoxShape.circle, color: container),
            child: Icon(widget.icon, size: _iconSize, color: onContainer),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton(
    CmpStatusMessageAction action,
    ColorScheme colorScheme,
  ) {
    return FilledButton.tonalIcon(
      onPressed: action.isBusy ? () {} : action.onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(200, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
      ),
      icon: action.isBusy
          ? CmpLoadingIndicator(
              size: 22,
              color: colorScheme.onSecondaryContainer,
            )
          : Icon(action.icon),
      label: Text(action.label),
    );
  }

  Widget _buildSecondaryButton(CmpStatusMessageAction action) {
    return TextButton.icon(
      onPressed: action.isBusy ? () {} : action.onPressed,
      style: TextButton.styleFrom(minimumSize: const Size(200, 48)),
      icon: action.isBusy
          ? const CmpLoadingIndicator(size: 20)
          : Icon(action.icon, size: 20),
      label: Text(action.label),
    );
  }
}
