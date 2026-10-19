import 'package:flutter/material.dart';

import '/features/profile/domain/entities/profile.dart';
import '/l10n/generated/app_localizations.dart';
import '../profile_labels.dart';

/// Scelta di un intento (☕🤝🙂✨) come chip, uguale nel profilo e nello
/// Start. Senza la spunta di Material 3, che prenderebbe il posto
/// dell'emoji: la scelta si riconosce dal riempimento `primaryContainer`,
/// dal bordo `primary` più spesso e dal testo in grassetto.
class CmpIntentChip extends StatelessWidget {
  const CmpIntentChip({
    super.key,
    required this.intent,
    required this.selected,
    required this.onSelected,
  });

  final MeetIntent intent;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ChoiceChip(
      showCheckmark: false,
      avatar: Text(ProfileLabels.intentEmoji(intent)),
      label: Text(ProfileLabels.intent(l10n, intent)),
      selected: selected,
      onSelected: onSelected,
      selectedColor: colorScheme.primaryContainer,
      side: selected
          ? BorderSide(color: colorScheme.primary, width: 1.5)
          : BorderSide(color: colorScheme.outlineVariant),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: selected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
    );
  }
}
