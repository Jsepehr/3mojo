import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/unlock_time_left.dart';
import '../providers/pro_paywall.dart';
import '../unlock_labels.dart';

/// Chip discreto in cima a "Vicinanze" mentre lo sblocco a pagamento è
/// attivo, al posto del banner d'acquisto: "Sbloccato · ancora 1 h 42 min".
/// Il tempo è in minuti interi e cambia una volta al minuto (`ProPaywall`):
/// nessun conto alla rovescia, nessun avviso "mancano 5 minuti". Negli
/// ultimi 10 minuti passa dai colori del primario a quelli del secondario,
/// senza animazioni.
///
/// Per i lettori di schermo il tempo è per esteso ("1 ora e 42 minuti") in
/// una live region: cambia — e quindi si annuncia — al massimo una volta al
/// minuto. Un tocco apre [showUnlockDetailsSheet].
class CmpUnlockChip extends StatelessWidget {
  const CmpUnlockChip({super.key});

  @override
  Widget build(BuildContext context) {
    final timeLeft = context.select<ProPaywall, UnlockTimeLeft?>(
      (p) => p.timeLeft,
    );
    if (timeLeft == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final endingSoon = timeLeft.isEndingSoon;
    final background = endingSoon
        ? colorScheme.secondaryContainer
        : colorScheme.primaryContainer;
    final foreground = endingSoon
        ? colorScheme.onSecondaryContainer
        : colorScheme.onPrimaryContainer;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          container: true,
          liveRegion: true,
          button: true,
          label: l10n.unlock_chip_semantics(
            UnlockLabels.spokenTimeLeft(l10n, timeLeft),
          ),
          onTap: () => showUnlockDetailsSheet(context),
          excludeSemantics: true,
          child: ActionChip(
            avatar: Icon(Icons.lock_open_rounded, color: foreground),
            label: Text(
              l10n.unlock_chip_label(UnlockLabels.timeLeft(l10n, timeLeft)),
            ),
            labelStyle: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: foreground),
            backgroundColor: background,
            side: BorderSide.none,
            shape: const StadiumBorder(),
            onPressed: () => showUnlockDetailsSheet(context),
          ),
        ),
      ),
    );
  }
}

/// Il piccolo dettaglio del chip: fino a che ora vale lo sblocco ("fino
/// alle 23:15", nel formato della lingua) e che il tempo scorre comunque.
/// Nient'altro. Se lo sblocco finisce mentre è aperto, si chiude da solo.
Future<void> showUnlockDetailsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ProPaywall>(),
        child: const _UnlockDetails(),
      ),
    );

class _UnlockDetails extends StatefulWidget {
  const _UnlockDetails();

  @override
  State<_UnlockDetails> createState() => _UnlockDetailsState();
}

class _UnlockDetailsState extends State<_UnlockDetails> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final expiresAt = context.select<ProPaywall, DateTime?>((p) => p.expiresAt);
    if (expiresAt == null) {
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.unlock_details_until(
                UnlockLabels.expiryTime(context, expiresAt),
              ),
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(l10n.unlock_details_time_runs, style: textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
