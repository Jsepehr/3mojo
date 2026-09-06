import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/features/encounters/presentation/providers/pro_encounters.dart';
import '/features/nearby/presentation/providers/pro_nearby.dart';
import '/features/nearby/presentation/widgets/cmp_nearby_person_tile.dart';
import '/features/nearby/presentation/widgets/cmp_nearby_waiting_overlay.dart';
import '/l10n/generated/app_localizations.dart';
import '../../domain/usecases/get_locked_nearby_people_usecase.dart';
import '../providers/pro_paywall.dart';
import 'cmp_paywall_banner.dart';

/// Sostituisce `CmpNearbyList` (feature `nearby`, che non sa nulla del
/// paywall) quando il paywall è attivo: stessa lista, ma con un terzo delle
/// persone più lontane visibili gratis e le altre sfocate/bloccate dietro
/// `CmpPaywallBanner`/`showPaywallConfirmDialog`. La composizione vive qui,
/// in `paywall/`, non dentro `nearby/`, per non far dipendere `nearby` da
/// una feature di monetizzazione che potrebbe anche non esistere.
class CmpPaywalledNearbyList extends StatelessWidget {
  const CmpPaywalledNearbyList({super.key});

  static const _getLockedNearbyPeopleUseCase = GetLockedNearbyPeopleUseCase();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proNearby = context.watch<ProNearby>();
    final proPaywall = context.watch<ProPaywall>();

    if (proNearby.isLoading) {
      return CmpNearbyWaitingOverlay(title: l10n.nearbyConnectingMessage);
    }

    if (proNearby.errorMessage != null) {
      return Center(child: Text(proNearby.errorMessage!));
    }

    if (proNearby.people.isEmpty) {
      return CmpNearbyWaitingOverlay(title: l10n.nearbyEmptyMessage);
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
            itemCount: lockedPeople.length,
            itemBuilder: (context, index) {
              final entry = lockedPeople[index];
              final person = entry.person;
              final alreadyRequested = proNearby.hasRequested(person.id);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Opacity(
                  opacity: alreadyRequested ? 0.4 : 1.0,
                  child: InkWell(
                    onTap: entry.isLocked
                        ? () => showPaywallConfirmDialog(context)
                        : alreadyRequested
                        ? null
                        : () {
                            context.read<ProEncounters>().sendRequest(
                              person.id,
                            );
                            context.read<ProNearby>().markRequested(
                              person.id,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.nearbyRequestSentMessage),
                              ),
                            );
                          },
                    child: CmpNearbyPersonTile(
                      person: person,
                      isLocked: entry.isLocked,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
