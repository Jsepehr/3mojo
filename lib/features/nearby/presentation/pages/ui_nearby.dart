import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../providers/pro_nearby.dart';
import '../widgets/cmp_nearby_person_tile.dart';

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
      itemBuilder: (context, index) =>
          CmpNearbyPersonTile(person: proNearby.people[index]),
    );
  }
}
