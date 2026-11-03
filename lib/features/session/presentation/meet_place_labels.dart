import '/features/session/domain/entities/meet_place.dart';
import '/l10n/generated/app_localizations.dart';

/// Testi ed emoji di ogni `MeetPlace`, in un solo posto: menu dello Start,
/// etichetta in "Vicinanze" e nelle richieste. Non è un widget: solo la
/// traduzione da valore di dominio a testo.
///
/// L'emoji non porta mai da sola il significato: chi la mostra la esclude
/// dallo screen reader, il testo accanto dice già tutto.
class MeetPlaceLabels {
  const MeetPlaceLabels._();

  static String emoji(MeetPlace place) => switch (place) {
    MeetPlace.bar => '🍺',
    MeetPlace.discoPub => '🍻',
    MeetPlace.cafe => '☕',
    MeetPlace.club => '🪩',
    MeetPlace.event => '🎤',
    MeetPlace.outdoors => '🌳',
    MeetPlace.other => '📍',
  };

  static String label(AppLocalizations l10n, MeetPlace place) =>
      switch (place) {
        MeetPlace.bar => l10n.place_bar,
        MeetPlace.discoPub => l10n.place_disco_pub,
        MeetPlace.cafe => l10n.place_cafe,
        MeetPlace.club => l10n.place_club,
        MeetPlace.event => l10n.place_event,
        MeetPlace.outdoors => l10n.place_outdoors,
        MeetPlace.other => l10n.place_other,
      };
}
