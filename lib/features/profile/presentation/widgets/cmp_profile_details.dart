import 'package:flutter/material.dart';

import '/features/profile/domain/entities/profile.dart';
import '/features/session/domain/entities/meet_place.dart';
import '/features/session/presentation/meet_place_labels.dart';
import '/l10n/generated/app_localizations.dart';
import '../profile_labels.dart';

/// Ciò che un'altra persona ha scelto di mostrare dal proprio profilo, in
/// piccolo: dove si trova (il luogo: emoji + testo, mai se è `other`), il genere solo se l'ha reso
/// visibile, e le lingue come codici ("IT · EN"). Mai chi cerca — quello non
/// arriva nemmeno al client. Tutto neutro: il rosso resta della probabilità
/// alta e del match.
///
/// Usato in "Vicinanze" e in "Qualcuno vuole conoscerti". Non disegna nulla
/// se non c'è niente da mostrare.
class CmpProfileDetails extends StatelessWidget {
  const CmpProfileDetails({
    super.key,
    this.place = MeetPlace.fallback,
    this.languages = const [],
    this.visibleGender,
    this.alignment = WrapAlignment.start,
  });

  final MeetPlace place;
  final List<String> languages;
  final Gender? visibleGender;
  final WrapAlignment alignment;

  static bool hasAny({
    MeetPlace place = MeetPlace.fallback,
    List<String> languages = const [],
    Gender? visibleGender,
  }) => place.isDeclared || languages.isNotEmpty || visibleGender != null;

  @override
  Widget build(BuildContext context) {
    final gender = visibleGender;
    if (!hasAny(place: place, languages: languages, visibleGender: gender)) {
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
        if (place.isDeclared)
          // L'emoji è decorativa: lo screen reader legge solo il testo.
          Semantics(
            label: MeetPlaceLabels.label(l10n, place),
            excludeSemantics: true,
            child: Text(
              '${MeetPlaceLabels.emoji(place)} '
              '${MeetPlaceLabels.label(l10n, place)}',
              style: style,
            ),
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
