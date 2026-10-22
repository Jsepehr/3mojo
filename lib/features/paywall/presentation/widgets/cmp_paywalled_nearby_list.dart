import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/nearby/presentation/providers/pro_nearby.dart';
import '/features/nearby/presentation/widgets/cmp_nearby_error_state.dart';
import '/features/nearby/presentation/widgets/cmp_nearby_person_tile.dart';
import '/features/nearby/presentation/widgets/cmp_nearby_waiting_overlay.dart';
import '/l10n/generated/app_localizations.dart';
import '../../domain/usecases/get_locked_nearby_people_usecase.dart';
import '../providers/pro_paywall.dart';
import 'cmp_paywall_banner.dart';

/// Corpo di "Vicinanze" (la home online): la lista delle persone presenti
/// ora, spinta dal server, con un terzo delle persone più lontane visibili
/// gratis e le altre sfocate/bloccate dietro
/// `CmpPaywallBanner`/`showPaywallConfirmDialog`. Compone i pezzi di
/// `nearby/` (stato, tile, attesa, errori) qui, in `paywall/`, per non far
/// dipendere `nearby` da una feature di monetizzazione.
///
/// Non conosce `encounters/` né `session/`: con chi c'è già una richiesta,
/// cosa fa un tap e come si chiude la sessione arrivano da fuori (`UiHome`)
/// — [requestStateOf], [onRequest], [onEndSession], [onRetakeSelfie]; e
/// così anche le azioni su una persona ([actionsOf]: Segnala/Blocca),
/// offerte solo a chi è libero dal paywall (una foto che non vedi non si
/// segnala; chi ti scrive lo blocchi dalla sua richiesta). Una
/// tile già richiesta ha la foto attenuata, un chip che dice perché, e non
/// è più cliccabile.
class CmpPaywalledNearbyList extends StatelessWidget {
  const CmpPaywalledNearbyList({
    super.key,
    required this.requestStateOf,
    required this.onRequest,
    this.onEndSession,
    this.onRetakeSelfie,
    this.actionsOf,
  });

  final CmpNearbyRequestState Function(String personId) requestStateOf;

  /// Tocco su una persona libera e non ancora richiesta: riceve la persona
  /// intera (foto, intento pubblico), per chi apre la tendina della
  /// proposta.
  final void Function(NearbyPerson person) onRequest;
  final VoidCallback? onEndSession;
  final VoidCallback? onRetakeSelfie;
  final Widget Function(NearbyPerson person)? actionsOf;

  static const _getLockedNearbyPeopleUseCase = GetLockedNearbyPeopleUseCase();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proNearby = context.watch<ProNearby>();
    final proPaywall = context.watch<ProPaywall>();

    if (proNearby.isLoading) {
      return CmpNearbyWaitingOverlay(title: l10n.connecting_to_the_server);
    }

    final failure = proNearby.failure;
    if (failure != null) {
      return CmpNearbyErrorState(
        failure: failure,
        isRetrying: proNearby.isRetrying,
        onRetry: proNearby.retry,
        onOpenLocationSettings: proNearby.openLocationSettings,
        onOpenAppSettings: proNearby.openAppSettings,
        onEndSession: onEndSession,
        onRetakeSelfie: onRetakeSelfie,
      );
    }

    if (proNearby.people.isEmpty) {
      return CmpNearbyWaitingOverlay(title: l10n.no_one_nearby_right_now);
    }

    final lockedPeople = _getLockedNearbyPeopleUseCase(
      proNearby.people,
      isUnlocked: proPaywall.isUnlocked,
    );
    final anyLocked = lockedPeople.any((entry) => entry.isLocked);

    return Column(
      children: [
        if (anyLocked) const CmpPaywallBanner(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: lockedPeople.length,
            itemBuilder: (context, index) {
              final entry = lockedPeople[index];
              final person = entry.person;
              final requestState = requestStateOf(person.id);

              return CmpNearbyPersonTile(
                person: person,
                isLocked: entry.isLocked,
                requestState: requestState,
                actions: entry.isLocked ? null : actionsOf?.call(person),
                onTap: entry.isLocked
                    ? () => showPaywallConfirmDialog(context)
                    : requestState != CmpNearbyRequestState.none
                    ? null
                    // Cosa proporre e l'invio li decide chi compone
                    // (`UiHome`, tendina della proposta); l'esito arriva da
                    // `CmpEncounterNoticeListener`.
                    : () => onRequest(person),
              );
            },
          ),
        ),
      ],
    );
  }
}
