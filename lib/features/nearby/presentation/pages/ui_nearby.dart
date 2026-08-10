import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../../../encounters/presentation/providers/pro_encounters.dart';
import '../providers/pro_nearby.dart';
import '../widgets/cmp_nearby_person_tile.dart';

/// Pagina "Vicinanze": lista delle persone presenti ora. Un tap su una
/// persona manda una richiesta d'incontro (feature `encounters`).
class UiNearby extends StatelessWidget {
  const UiNearby({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proNearby = context.watch<ProNearby>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.nearbyPageTitle)),
      body: RefreshIndicator(
        onRefresh: () => context.read<ProNearby>().loadNearbyPeople(),
        child: _NearbyBody(l10n: l10n, proNearby: proNearby),
      ),
    );
  }
}

class _NearbyBody extends StatelessWidget {
  const _NearbyBody({required this.l10n, required this.proNearby});

  final AppLocalizations l10n;
  final ProNearby proNearby;

  @override
  Widget build(BuildContext context) {
    if (proNearby.isLoading) {
      return const Center(child: CircularProgressIndicator());
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
        return InkWell(
          onTap: () {
            context.read<ProEncounters>().sendRequest(
              person.id,
              person.photoUrl,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.nearbyRequestSentMessage)),
            );
          },
          child: CmpNearbyPersonTile(person: person),
        );
      },
    );
  }
}
