import 'dart:ui';

import 'package:flutter/material.dart';

import '/core/demo/demo_mode.dart';
import '/core/theme/raen_colors.dart';
import '/core/utils/photo_data_uri.dart';
import '/core/widgets/cmp_demo_badge.dart';
import '/core/widgets/cmp_photo.dart';
import '/core/widgets/cmp_status_chip.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/profile/presentation/widgets/cmp_profile_details.dart';
import '/l10n/generated/app_localizations.dart';

/// C'è già una richiesta con questa persona, e in che verso: la tile non lo
/// calcola (`nearby` non conosce `encounters`), lo riceve da chi la compone.
enum CmpNearbyRequestState {
  /// Nessuna richiesta: la tile è cliccabile.
  none,

  /// L'hai chiesta tu (o sta partendo): "Richiesta inviata".
  sent,

  /// È lei che ha chiesto te e aspetta la tua risposta in "Richieste".
  received,
}

/// Riga della lista "Vicinanze": nessun nome (l'app non lo chiede) e nessuna
/// distanza (il server non la manda: ordina lui la lista e decide il
/// paywall) — solo una foto grande e lo stadio di probabilità d'incontro
/// (Bassa/Media/Alta, come chip colorato) — niente barra di caricamento, dato che
/// sono solo tre stadi discreti, non un valore continuo.
/// `isLocked` (paywall, `features/paywall/`) sfoca solo la foto — la
/// probabilità resta visibile anche bloccata, è proprio quel poco di
/// informazione a dare un motivo per sbloccare la foto vera.
///
/// Con una richiesta già in corso ([requestState]) si attenua solo la foto
/// (il testo resta leggibile) e un chip dice perché la tile non risponde
/// più al tocco. Il tocco ([onTap]) è dentro la `Card`, ritagliato ai suoi
/// angoli: l'effetto ripple si vede.
///
/// [actions] (facoltativo, in fondo alla riga) è ciò che chi compone vuole
/// offrire su questa persona — in "Vicinanze" il menu "⋯" con Segnala e
/// Blocca (`safety/`): `nearby` non sa cosa contiene. Ha il suo tocco, che
/// non apre la tendina della proposta.
class CmpNearbyPersonTile extends StatelessWidget {
  const CmpNearbyPersonTile({
    super.key,
    required this.person,
    this.isLocked = false,
    this.requestState = CmpNearbyRequestState.none,
    this.onTap,
    this.actions,
  });

  final NearbyPerson person;
  final bool isLocked;
  final CmpNearbyRequestState requestState;
  final VoidCallback? onTap;
  final Widget? actions;

  /// Margini della card nella lista: gli stessi 16 px ai lati del banner
  /// del paywall e delle schede delle richieste.
  static const EdgeInsets margin = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 6,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final photo = imageProviderForPhoto(person.photoBytes);
    final isRequested = requestState != CmpNearbyRequestState.none;

    return Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Photo(photo: photo, isLocked: isLocked, isDimmed: isRequested),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Nella demo dichiarata: ogni persona è dimostrativa.
                    if (DemoMode.isActive(context)) ...[
                      const CmpDemoBadge(),
                      const SizedBox(height: 8),
                    ],
                    _MeetingChanceChip(
                      chance: person.meetingChance,
                      label: _meetingChanceLabel(l10n, person.meetingChance),
                    ),
                    if (isRequested) ...[
                      const SizedBox(height: 8),
                      _RequestChip(state: requestState),
                    ],
                    if (_hasDetails) ...[
                      const SizedBox(height: 8),
                      CmpProfileDetails(
                        intent: person.intent,
                        languages: person.languages,
                        visibleGender: person.visibleGender,
                      ),
                    ],
                  ],
                ),
              ),
              ?actions,
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasDetails => CmpProfileDetails.hasAny(
    intent: person.intent,
    languages: person.languages,
    visibleGender: person.visibleGender,
  );

  String _meetingChanceLabel(AppLocalizations l10n, MeetingChance chance) {
    switch (chance) {
      case MeetingChance.low:
        return l10n.low_chance_to_meet;
      case MeetingChance.medium:
        return l10n.medium_chance_to_meet;
      case MeetingChance.high:
        return l10n.high_chance_to_meet;
    }
  }
}

/// Perché la tile non è più cliccabile: richiesta tua in corso (pieno
/// neutro, spunta) o sua in attesa di risposta (solo bordo e cuore
/// rosso-cuore: una buona notizia, ma diversa a colpo d'occhio dal chip
/// pieno della probabilità).
class _RequestChip extends StatelessWidget {
  const _RequestChip({required this.state});

  final CmpNearbyRequestState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final raen = RaenColors.of(context);

    return switch (state) {
      CmpNearbyRequestState.received => CmpStatusChip(
        label: l10n.wants_to_meet_you,
        icon: Icons.favorite,
        iconColor: raen.heart,
        foreground: colorScheme.onSurface,
        outlined: true,
        borderColor: raen.heart,
      ),
      _ => CmpStatusChip(
        label: l10n.request_sent,
        icon: Icons.check,
        background: colorScheme.secondaryContainer,
        foreground: colorScheme.onSecondaryContainer,
      ),
    };
  }
}

/// Stadio di probabilità come chip, tutto nella scala del blu tranne "alta":
/// bassa neutra, media blu tenue col cuore vuoto, alta rosso-cuore col cuore
/// pieno. Il rosso qui significa "buona notizia", mai "male" — per quello
/// c'è `colorScheme.error`.
class _MeetingChanceChip extends StatelessWidget {
  const _MeetingChanceChip({required this.chance, required this.label});

  final MeetingChance chance;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final raen = RaenColors.of(context);

    final (background, foreground, icon, iconColor) = switch (chance) {
      MeetingChance.low => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
        null,
        null,
      ),
      MeetingChance.medium => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        Icons.favorite_border,
        colorScheme.onPrimaryContainer,
      ),
      MeetingChance.high => (
        raen.heartContainer,
        raen.onHeartContainer,
        Icons.favorite,
        raen.heart,
      ),
    };

    return CmpStatusChip(
      label: label,
      icon: icon,
      iconColor: iconColor,
      background: background,
      foreground: foreground,
    );
  }
}

/// Foto della tile, sfocata con un lucchetto sopra quando bloccata dal
/// paywall — la stessa `CmpPhoto` di sempre, solo con un filtro applicato.
/// Attenuata ([isDimmed]) se c'è già una richiesta con questa persona.
class _Photo extends StatelessWidget {
  const _Photo({
    required this.photo,
    required this.isLocked,
    required this.isDimmed,
  });

  final ImageProvider? photo;
  final bool isLocked;
  final bool isDimmed;

  static const double _dimmedOpacity = 0.4;

  @override
  Widget build(BuildContext context) {
    final image = _buildImage(context);
    return isDimmed ? Opacity(opacity: _dimmedOpacity, child: image) : image;
  }

  Widget _buildImage(BuildContext context) {
    final image = CmpPhoto(image: photo, size: 96);
    if (!isLocked) return image;

    final raen = RaenColors.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: image,
        ),
        Icon(
          Icons.lock,
          color: raen.onPhoto,
          size: 28,
          shadows: [Shadow(color: raen.photoScrim, blurRadius: 6)],
        ),
      ],
    );
  }
}
