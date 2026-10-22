import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';
import '../domain/entities/unlock_time_left.dart';

/// Testi (tradotti) del tempo che resta di uno sblocco: la forma breve del
/// chip ("1 h 42 min", "meno di un minuto") e quella per esteso per i lettori
/// di schermo ("1 ora e 42 minuti"). Solo ore e minuti, mai secondi.
class UnlockLabels {
  const UnlockLabels._();

  static String timeLeft(AppLocalizations l10n, UnlockTimeLeft timeLeft) {
    final UnlockTimeLeft(:hours, :minutes) = timeLeft;
    if (hours > 0 && minutes > 0) {
      return l10n.unlock_time_hours_minutes(hours, minutes);
    }
    if (hours > 0) return l10n.unlock_time_hours(hours);
    if (minutes > 0) return l10n.unlock_time_minutes(minutes);
    return l10n.unlock_time_less_than_a_minute;
  }

  static String spokenTimeLeft(AppLocalizations l10n, UnlockTimeLeft timeLeft) {
    final UnlockTimeLeft(:hours, :minutes) = timeLeft;
    if (hours > 0 && minutes > 0) {
      return l10n.unlock_spoken_hours_and_minutes(
        l10n.unlock_spoken_hours(hours),
        l10n.unlock_spoken_minutes(minutes),
      );
    }
    if (hours > 0) return l10n.unlock_spoken_hours(hours);
    if (minutes > 0) return l10n.unlock_spoken_minutes(minutes);
    return l10n.unlock_time_less_than_a_minute;
  }

  /// L'ora di fine nel formato della lingua e dell'impostazione 12/24 h del
  /// telefono (es. "23:15", "11:15 PM").
  static String expiryTime(BuildContext context, DateTime expiresAt) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(expiresAt.toLocal()),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
}
