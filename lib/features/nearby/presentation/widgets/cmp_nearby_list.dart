import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/core/widgets/cmp_loading_indicator.dart';
import '/l10n/generated/app_localizations.dart';
import '../../../encounters/presentation/providers/pro_encounters.dart';
import '../providers/pro_nearby.dart';
import 'cmp_nearby_person_tile.dart';

/// Corpo di "Vicinanze": lista delle persone presenti ora — aggiornata da
/// sola, il server la spinge appena cambia qualcosa (nessun pull-to-refresh:
/// non c'è più nulla da richiedere a mano, la connessione è già aperta).
/// Un tap su una persona manda una richiesta d'incontro (feature `encounters`).
/// Una sola richiesta a testa finché resta nel perimetro: dopo il tap la
/// tile si vede in grigio e non è più cliccabile (`ProNearby.hasRequested`).
/// Senza `Scaffold`/`AppBar` propri: pensato per stare nel body di un'altra
/// pagina (la home online), non per essere una pagina a sé.
class CmpNearbyList extends StatelessWidget {
  const CmpNearbyList({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proNearby = context.watch<ProNearby>();

    return _NearbyBody(l10n: l10n, proNearby: proNearby);
  }
}

class _NearbyBody extends StatelessWidget {
  const _NearbyBody({required this.l10n, required this.proNearby});

  final AppLocalizations l10n;
  final ProNearby proNearby;

  @override
  Widget build(BuildContext context) {
    if (proNearby.isLoading) {
      return const Center(child: CmpLoadingIndicator());
    }

    if (proNearby.errorMessage != null) {
      return Center(child: Text(proNearby.errorMessage!));
    }

    if (proNearby.people.isEmpty) {
      return Center(child: Text(l10n.nearbyEmptyMessage));
    }

    return ListView.builder(
      itemCount: proNearby.people.length,
      itemBuilder: (context, index) {
        final person = proNearby.people[index];
        final alreadyRequested = proNearby.hasRequested(person.id);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Opacity(
            opacity: alreadyRequested ? 0.4 : 1.0,
            child: InkWell(
              onTap: alreadyRequested
                  ? null
                  : () {
                      context.read<ProEncounters>().sendRequest(person.id);
                      context.read<ProNearby>().markRequested(person.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.nearbyRequestSentMessage)),
                      );
                    },
              child: CmpNearbyPersonTile(person: person),
            ),
          ),
        );
      },
    );
  }
}
