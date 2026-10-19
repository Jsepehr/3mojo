import 'package:flutter/material.dart';

import '/core/errors/failures.dart';
import '/core/widgets/cmp_status_message.dart';
import '/l10n/generated/app_localizations.dart';

/// Corpo di "Vicinanze" quando la lista non si può mostrare: sceglie icona,
/// testi tradotti e azioni dal **tipo** di [failure] — mai il suo
/// `message`, che è un dettaglio tecnico (spesso in inglese o con il nome
/// di un'eccezione) e non va a schermo.
///
/// - `ConnectionFailure` (offline, server irraggiungibile): onde che
///   pulsano, perché l'app sta già riprovando da sola; bottone Riprova.
/// - `LocationDisabledFailure`: apre le impostazioni della localizzazione.
/// - `LocationPermissionFailure`: apre le impostazioni dell'app.
/// - `SelfieRejectedByServerFailure`: il server non ha accettato il selfie;
///   si chiude la sessione e si rifà lo Start ([onRetakeSelfie]).
/// - `SelfieNotUsableFailure`: il selfie non si è potuto preparare per
///   l'invio sul telefono; stessa via d'uscita ([onRetakeSelfie]).
/// - `TooManyStartsFailure`: troppi Start dalla stessa rete; l'app riprova
///   da sola più avanti, oppure si chiude la sessione ([onEndSession]).
/// - qualsiasi altro: errore generico, solo Riprova.
///
/// Senza stato e senza provider: riceve tutto da chi lo usa
/// (`CmpPaywalledNearbyList`, che legge `ProNearby`). Chiudere la sessione
/// non è affare di `nearby`: [onEndSession]/[onRetakeSelfie] arrivano da
/// fuori (la home); se mancano, quel bottone non c'è.
class CmpNearbyErrorState extends StatelessWidget {
  const CmpNearbyErrorState({
    super.key,
    required this.failure,
    required this.isRetrying,
    required this.onRetry,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
    this.onEndSession,
    this.onRetakeSelfie,
  });

  final Failure failure;
  final bool isRetrying;
  final VoidCallback onRetry;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onOpenAppSettings;
  final VoidCallback? onEndSession;
  final VoidCallback? onRetakeSelfie;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final retry = CmpStatusMessageAction(
      label: l10n.retry,
      icon: Icons.refresh_rounded,
      onPressed: onRetry,
      isBusy: isRetrying,
    );

    return switch (failure) {
      ConnectionFailure() => CmpStatusMessage(
        icon: Icons.wifi_off_rounded,
        title: l10n.nearby_error_connection_title,
        message: l10n.nearby_error_connection_body,
        pulse: true,
        primaryAction: retry,
      ),
      LocationDisabledFailure() => CmpStatusMessage(
        icon: Icons.location_off_rounded,
        title: l10n.nearby_error_location_disabled_title,
        message: l10n.nearby_error_location_disabled_body,
        primaryAction: CmpStatusMessageAction(
          label: l10n.turn_on_location,
          icon: Icons.my_location_rounded,
          onPressed: onOpenLocationSettings,
        ),
        secondaryAction: retry,
      ),
      LocationPermissionFailure() => CmpStatusMessage(
        icon: Icons.location_disabled_rounded,
        title: l10n.nearby_error_location_permission_title,
        message: l10n.nearby_error_location_permission_body,
        primaryAction: CmpStatusMessageAction(
          label: l10n.open_settings,
          icon: Icons.settings_rounded,
          onPressed: onOpenAppSettings,
        ),
        secondaryAction: retry,
      ),
      SelfieRejectedByServerFailure() => CmpStatusMessage(
        icon: Icons.no_photography_outlined,
        title: l10n.selfie_rejected_by_server_title,
        message: l10n.selfie_rejected_by_server_body,
        tone: CmpStatusMessageTone.error,
        primaryAction: onRetakeSelfie == null
            ? null
            : CmpStatusMessageAction(
                label: l10n.end_and_retake_selfie,
                icon: Icons.camera_alt_outlined,
                onPressed: onRetakeSelfie!,
              ),
      ),
      SelfieNotUsableFailure() => CmpStatusMessage(
        icon: Icons.no_photography_outlined,
        title: l10n.selfie_not_usable_title,
        message: l10n.selfie_not_usable_body,
        tone: CmpStatusMessageTone.error,
        primaryAction: onRetakeSelfie == null
            ? null
            : CmpStatusMessageAction(
                label: l10n.end_and_retake_selfie,
                icon: Icons.camera_alt_outlined,
                onPressed: onRetakeSelfie!,
              ),
      ),
      TooManyStartsFailure() => CmpStatusMessage(
        icon: Icons.hourglass_top_rounded,
        title: l10n.too_many_starts_title,
        message: l10n.too_many_starts_body,
        pulse: true,
        primaryAction: onEndSession == null
            ? null
            : CmpStatusMessageAction(
                label: l10n.end_session,
                icon: Icons.stop_circle_outlined,
                onPressed: onEndSession!,
              ),
      ),
      _ => CmpStatusMessage(
        icon: Icons.error_outline_rounded,
        title: l10n.nearby_error_generic_title,
        message: l10n.nearby_error_generic_body,
        tone: CmpStatusMessageTone.error,
        primaryAction: retry,
      ),
    };
  }
}
