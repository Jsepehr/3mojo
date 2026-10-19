import 'package:flutter/material.dart';

import '/features/profile/domain/entities/profile.dart';
import '/l10n/generated/app_localizations.dart';
import '../profile_labels.dart';

/// Ciò che un'altra persona ha scelto di mostrare dal proprio profilo, in
/// piccolo: cosa cerca (emoji + testo), il genere solo se l'ha reso
/// visibile, e le lingue come codici ("IT · EN"). Mai chi cerca — quello non
/// arriva nemmeno al client. Tutto neutro: il rosso resta della probabilità
/// alta e del match.
///
/// Usato in "Vicinanze" e in "Qualcuno vuole conoscerti". Non disegna nulla
/// se non c'è niente da mostrare.
class CmpProfileDetails extends StatelessWidget {
  const CmpProfileDetails({
    super.key,
    this.intent,
    this.languages = const [],
    this.visibleGender,
    this.alignment = WrapAlignment.start,
  });

  final MeetIntent? intent;
  final List<String> languages;
  final Gender? visibleGender;
  final WrapAlignment alignment;

  static bool hasAny({
    MeetIntent? intent,
    List<String> languages = const [],
    Gender? visibleGender,
  }) => intent != null || languages.isNotEmpty || visibleGender != null;

  @override
  Widget build(BuildContext context) {
    final intent = this.intent;
    final gender = visibleGender;
    if (!hasAny(intent: intent, languages: languages, visibleGender: gender)) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Wrap(
      alignment: alignment,
      spacing: 12,
      runSpacing: 4,
      children: [
        if (intent != null)
          Text(
            '${ProfileLabels.intentEmoji(intent)} '
            '${ProfileLabels.intent(l10n, intent)}',
            style: style,
          ),
        if (gender != null)
          Text(ProfileLabels.gender(l10n, gender), style: style),
        if (languages.isNotEmpty)
          Text(
            languages.map((code) => code.toUpperCase()).join(' · '),
            style: style,
          ),
      ],
    );
  }
}
